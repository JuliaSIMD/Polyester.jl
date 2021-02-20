
import .ForwardDiff

const DiffResult = ForwardDiff.DiffResults.DiffResult

function cld_fast(n, d)
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
    batch((d,min(d,VectorizationBase.num_threads())), r, Δx, x) do rΔxx,start,stop
        evaluate_chunks!(f, rΔxx, start, stop, ForwardDiff.Chunk{C}())
    end
    r[]
end


