
import .ForwardDiff

const DiffResult = ForwardDiff.DiffResults.DiffResult

function cld_fast(a::A,b::B) where {A,B}
    T = promote_type(A,B)
    cld_fast(a%T,b%T)
end
function cld_fast(n::T, d::T) where {T}
    x = Base.udiv_int(n, d)
    x += n != d*x
end

store_val!(r::Base.RefValue{T}, x::T) where {T} = (r[] = x)
store_val!(r::Ptr{T}, x::T) where {T} = Base.unsafe_store!(r, x)

function evaluate_chunks!(f::F, (r,Δx,x), start, stop, ::ForwardDiff.Chunk{C}) where {F,C}
    cfg = ForwardDiff.GradientConfig(f, x, ForwardDiff.Chunk{C}(), nothing)
    N = length(x)
    last_stop = cld_fast(N, C)
    is_last = last_stop == stop
    stop -= is_last

    xdual = cfg.duals
    seeds = cfg.seeds
    ForwardDiff.seed!(xdual, x)
    for c ∈ start:stop
        i = (c-1) * C + 1
        ForwardDiff.seed!(xdual, x, i, seeds)
        ydual = f(xdual)
        ForwardDiff.extract_gradient_chunk!(Nothing, Δx, ydual, i, C)
        ForwardDiff.seed!(xdual, x, i)
    end
    if is_last
        lastchunksize = C + N - last_stop*C
        lastchunkindex = N - lastchunksize + 1
        ForwardDiff.seed!(xdual, x, lastchunkindex, seeds, lastchunksize)
        _ydual = f(xdual)
        ForwardDiff.extract_gradient_chunk!(Nothing, Δx, _ydual, lastchunkindex, lastchunksize)
        store_val!(r, ForwardDiff.value(_ydual))
    end
end

function threaded_gradient!(f::F, Δx::AbstractVector, x::AbstractVector, ::ForwardDiff.Chunk{C}) where {F,C}
    N = length(x)
    d = cld_fast(N, C)
    r = Ref{eltype(Δx)}()
    batch((d,min(d,num_threads())), r, Δx, x) do rΔxx,start,stop
        evaluate_chunks!(f, rΔxx, start, stop, ForwardDiff.Chunk{C}())
    end
    r[]
end

#### in-place jac, out-of-place f ####

function evaluate_jacobian_chunks!(f::F, (Δx,x), start, stop, ::ForwardDiff.Chunk{C}) where {F,C}
    cfg = ForwardDiff.JacobianConfig(f, x, ForwardDiff.Chunk{C}(), nothing)

    # figure out loop bounds
    N = length(x)
    last_stop = cld_fast(N, C)
    is_last = last_stop == stop
    stop -= is_last

    # seed work arrays
    xdual = cfg.duals
    ForwardDiff.seed!(xdual, x)
    seeds = cfg.seeds

    # handle intermediate chunks
    for c ∈ start:stop
        # compute xdual
        i = (c-1) * C + 1
        ForwardDiff.seed!(xdual, x, i, seeds)
        
        # compute ydual
        ydual = f(xdual)

        # extract part of the Jacobian
        Δx_reshaped = ForwardDiff.reshape_jacobian(Δx, ydual, xdual)
        ForwardDiff.extract_jacobian_chunk!(Nothing, Δx_reshaped, ydual, i, C)
        ForwardDiff.seed!(xdual, x, i)
    end

    # handle the last chunk
    if is_last
        lastchunksize = C + N - last_stop*C
        lastchunkindex = N - lastchunksize + 1

        # compute xdual
        ForwardDiff.seed!(xdual, x, lastchunkindex, seeds, lastchunksize)
        
        # compute ydual
        _ydual = f(xdual)
        
        # extract part of the Jacobian
        _Δx_reshaped = ForwardDiff.reshape_jacobian(Δx, _ydual, xdual)
        ForwardDiff.extract_jacobian_chunk!(Nothing, _Δx_reshaped, _ydual, lastchunkindex, lastchunksize)
    end
end

function threaded_jacobian!(f::F, Δx::AbstractArray, x::AbstractArray, ::ForwardDiff.Chunk{C}) where {F,C}
    N = length(x)
    d = cld_fast(N, C)
    batch((d,min(d,num_threads())), Δx, x) do Δxx,start,stop
        evaluate_jacobian_chunks!(f, Δxx, start, stop, ForwardDiff.Chunk{C}())
    end
    return Δx
end

# # #### in-place jac, in-place f ####

function evaluate_f_and_jacobian_chunks!(f!::F, (y,Δx,x), start, stop, ::ForwardDiff.Chunk{C}) where {F,C}
    cfg = ForwardDiff.JacobianConfig(f!, y, x, ForwardDiff.Chunk{C}(), nothing)

    # figure out loop bounds
    N = length(x)
    last_stop = cld_fast(N, C)
    is_last = last_stop == stop
    stop -= is_last

    # seed work arrays
    ydual, xdual = cfg.duals
    ForwardDiff.seed!(xdual, x)
    seeds = cfg.seeds
    Δx_reshaped = ForwardDiff.reshape_jacobian(Δx, ydual, xdual)

    # handle intermediate chunks
    for c ∈ start:stop
        # compute xdual
        i = (c-1) * C + 1
        ForwardDiff.seed!(xdual, x, i, seeds)
        
        # compute ydual
        f!(ForwardDiff.seed!(ydual, y), xdual)

        # extract part of the Jacobian
        ForwardDiff.extract_jacobian_chunk!(Nothing, Δx_reshaped, ydual, i, C)
        ForwardDiff.seed!(xdual, x, i)
    end

    # handle the last chunk
    if is_last
        lastchunksize = C + N - last_stop*C
        lastchunkindex = N - lastchunksize + 1

        # compute xdual
        ForwardDiff.seed!(xdual, x, lastchunkindex, seeds, lastchunksize)
        
        # compute ydual
        f!(ForwardDiff.seed!(ydual, y), xdual)
        
        # extract part of the Jacobian
        ForwardDiff.extract_jacobian_chunk!(Nothing, Δx_reshaped, ydual, lastchunkindex, lastchunksize)
        map!(ForwardDiff.value, y, ydual)
    end
end

function threaded_jacobian!(f!::F, y::AbstractArray, Δx::AbstractArray, x::AbstractArray, ::ForwardDiff.Chunk{C}) where {F,C}
    N = length(x)
    d = cld_fast(N, C)
    batch((d,min(d,num_threads())), y, Δx, x) do yΔxx,start,stop
        evaluate_f_and_jacobian_chunks!(f!, yΔxx, start, stop, ForwardDiff.Chunk{C}())
    end
    Δx
end
