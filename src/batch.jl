struct BatchClosure{F, A, B}
    f::F
end
function (b::BatchClosure{F,A,B})(p::Ptr{UInt}) where {F,A,B}
    (offset, args) = ThreadingUtilities.load(p, A, 2*sizeof(UInt))
    (offset, start) = ThreadingUtilities.load(p, UInt, offset)
    (offset, stop ) = ThreadingUtilities.load(p, UInt, offset)
    b.f(args, start+one(UInt), stop)
    B && free_local_threads!()
    nothing
end

@inline function batch_closure(f::F, args::A, ::Val{B}) where {F,A,B}
    bc = BatchClosure{F,A,B}(f)
    @cfunction($bc, Cvoid, (Ptr{UInt},))
end

@inline function setup_batch!(p::Ptr{UInt}, fptr::Ptr{Cvoid}, argtup, start::UInt, stop::UInt)
    offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
    offset = ThreadingUtilities.store!(p, argtup, offset)
    offset = ThreadingUtilities.store!(p, start, offset)
    offset = ThreadingUtilities.store!(p, stop, offset)
    nothing
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop)
    fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
    ThreadingUtilities.launch(tid, fptr, argtup, start, stop) do p, fptr, argtup, start, stop
        setup_batch!(p, fptr, argtup, start, stop)
    end
end

function add_var!(q, argtup, gcpres, ::Type{T}, argtupname, gcpresname, k) where {T}
    parg_k = Symbol(argtupname, :_, k)
    garg_k = Symbol(gcpresname, :_, k)
    if T <: Tuple
        push!(q.args, Expr(:(=), parg_k, Expr(:ref, argtupname, k)))
        t = Expr(:tuple)
        for (j,p) ∈ enumerate(T.parameters)
            add_var!(q, t, gcpres, p, parg_k, garg_k, j)
        end
        push!(argtup.args, t)
    else
        push!(q.args, Expr(:(=), Expr(:tuple, parg_k, garg_k), Expr(:call, :object_and_preserve, Expr(:ref, argtupname, k))))
        push!(argtup.args, parg_k)
        push!(gcpres.args, garg_k)
    end
end


@generated function _batch_no_reserve(
    f!::F, threadmask, nthread, torelease, Nr, Nd, ulen, args::Vararg{Any,K}
) where {F,K}
    q = quote
        threads = UnsignedIteratorEarlyStop(threadmask, nthread)
        Ndp = Nd + one(Nd)
    end
    block = quote
        start = zero(UInt)
        i = 0x00000000
        tid = 0x00000000
        tm = mask(threads)
        while true
            VectorizationBase.assume(tm ≠ zero(tm))
            tz = trailing_zeros(tm) % UInt32
            stop = start + ifelse(i < Nr, Ndp, Nd)
            i += 0x00000001
            tz += 0x00000001
            tid += tz
            tm >>>= tz
            launch_batched_thread!(cfunc, tid, argtup, start, stop)
            start = stop
            i == nthread && break
        end
        f!(map(dereference, argtup), start+one(UInt), ulen)
        tm = mask(threads)
        tid = 0x00000000
        while true
            VectorizationBase.assume(tm ≠ zero(tm))
            tz = trailing_zeros(tm) % UInt32
            tz += 0x00000001
            tm >>>= tz
            tid += tz
            ThreadingUtilities.wait(tid)
            iszero(tm) && break
        end
        free_threads!(torelease)
        nothing
    end
    gcpr = Expr(:gc_preserve, block, :cfunc)
    argt = Expr(:tuple)
    for k ∈ 1:K
        add_var!(q, argt, gcpr, args[k], :args, :gcp, k)
    end
    push!(q.args, :(argtup = $argt), :(cfunc = batch_closure(f!, argtup, Val{false}())), gcpr)
    push!(q.args, nothing)
    q
end
@generated function _batch_reserve(
    f!::F, threadmask, nthread, unused_threads, torelease, Nr, Nd, ulen, args::Vararg{Any,K}
) where {F,K}
    q = quote
        nbatch = nthread + one(nthread)
        threads = UnsignedIteratorEarlyStop(threadmask, nthread)
        Ndp = Nd + one(Nd)
        nres_per = Base.udiv_int(unused_threads, nbatch)
        nres_rem = unused_threads - nres_per * nbatch
        nres_prr = nres_per + one(nres_per)
    end
    block = quote
        start = zero(UInt)
        i = zero(nres_rem)
        tid = 0x00000000
        tm = mask(threads)
        wait_mask = zero(worker_type())
        while true
            VectorizationBase.assume(tm ≠ zero(tm))
            tz = trailing_zeros(tm) % UInt32
            reserve = ifelse(i < nres_rem, nres_prr, nres_per)
            tz += 0x00000001
            stop = start + ifelse(i < Nr, Ndp, Nd)
            tid += tz
            tid_to_launch = tid
            wait_mask |= (one(wait_mask) << (tid - one(tid)))
            tm >>>= tz
            reserved_threads = zero(worker_type())
            for _ ∈ 1:reserve
                VectorizationBase.assume(tm ≠ zero(tm))
                tz = trailing_zeros(tm) % UInt32
                tz += 0x00000001
                tid += tz
                tm >>>= tz
                reserved_threads |= (one(reserve) << (tid - one(tid)))
            end
            reserve_threads!(tid_to_launch, reserved_threads)
            launch_batched_thread!(cfunc, tid_to_launch, argtup, start, stop)
            i += one(i)
            start = stop
            i == nthread && break
        end
        f!(map(dereference, argtup), start+one(UInt), ulen)
        tid = 0x00000000
        while true
            VectorizationBase.assume(wait_mask ≠ zero(wait_mask))
            tz = (trailing_zeros(wait_mask) % UInt32) + 0x00000001
            wait_mask >>>= tz
            tid += tz
            ThreadingUtilities.wait(tid)
            iszero(wait_mask) && break
        end
        nothing
    end
    gcpr = Expr(:gc_preserve, block, :cfunc)
    argt = Expr(:tuple)
    for k ∈ 1:K
        add_var!(q, argt, gcpr, args[k], :args, :gcp, k)
    end
    push!(q.args, :(argtup = $argt), :(cfunc = batch_closure(f!, argtup, Val{true}())), gcpr)
    push!(q.args, nothing)
    q
end


function batch(
    f!::F, (len, nbatches)::Tuple{Vararg{Integer,2}}, args::Vararg{Any,K}
) where {F,K}
    threads, torelease = request_threads(Base.Threads.threadid(), nbatches - one(nbatches))
    nthread = length(threads)
    ulen = len % UInt
    if iszero(nthread)
        f!(args, one(UInt), ulen)
        return
    end
    nbatch = nthread + one(nthread)
    
    Nd = Base.udiv_int(ulen, nbatch % UInt) # reasonable for `ulen` to be ≥ 2^32
    Nr = ulen - Nd * nbatch
    
    _batch_no_reserve(f!, mask(threads), nthread, torelease, Nr, Nd, ulen, args...)
end
function batch(
    f!::F, (len, nbatches, reserve_per_worker)::Tuple{Vararg{Integer,3}}, args::Vararg{Any,K}
) where {F,K}
    ulen = len % UInt
    nbatches ≤ 1 && @goto NOTHREADS
    requested_threads = reserve_per_worker*nbatches
    threads, torelease = request_threads(Base.Threads.threadid(), requested_threads - one(nbatches))
    nthread = length(threads)
    iszero(nthread) && @goto NOTHREADS
    total_threads = nthread + one(nthread)
    nbatch = min(total_threads, nbatches % UInt32)
    
    Nd = Base.udiv_int(ulen, nbatch % UInt)
    Nr = ulen - Nd * nbatch

    unused_threads = total_threads - nbatch
    if iszero(unused_threads)
        _batch_no_reserve(f!, mask(threads), nthread, torelease, Nr, Nd, ulen, args...)
    else
        _batch_reserve(f!, mask(threads), nbatch-one(nbatch), unused_threads, torelease, Nr, Nd, ulen, args...)
    end
    return nothing
    @label NOTHREADS
    f!(args, one(UInt), ulen)
    return nothing
end


