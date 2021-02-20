
struct UnsignedIterator{U}
    u::U
end

Base.IteratorSize(::Type{<:UnsignedIterator}) = Base.HasShape{1}()
Base.IteratorEltype(::Type{<:UnsignedIterator}) = Base.HasEltype()

Base.eltype(::UnsignedIterator) = UInt32
Base.length(u::UnsignedIterator) = count_ones(u.u)
Base.size(u::UnsignedIterator) = (count_ones(u.u),)

# @inline function Base.iterate(u::UnsignedIterator, uu = u.u)
#     tz = trailing_zeros(uu) % UInt32
#     # tz ≥ 0x00000020 && return nothing
#     tz > 0x0000001f && return nothing
#     uu ⊻= (0x00000001 << tz)
#     tz, uu
# end
@inline function Base.iterate(u::UnsignedIterator, (i,uu) = (0x00000000,u.u))
    tz = trailing_zeros(uu) % UInt32
    tz == 0x00000020 && return nothing
    i += tz
    tz += 0x00000001
    uu >>>= tz
    (i, (i+0x00000001,uu))
end


"""
    UnsignedIteratorEarlyStop(thread_mask[, num_threads = count_ones(thread_mask)])

Iterator, returning `(i,t) = Tuple{UInt32,UInt32}`, where `i` iterates from `1,2,...,num_threads`, and `t` gives the threadids to call `ThreadingUtilities.taskpointer` with.


Unfortunately, codegen is suboptimal when used in the ergonomic `for (i,tid) ∈ thread_iterator` fashion. If you want to microoptimize,
You'd get better performance from a pattern like:
```julia
function sumk(u,l = count_ones(u) % UInt32)
    uu = ServiceSolicitation.UnsignedIteratorEarlyStop(u,l)
    s = zero(UInt32); state = ServiceSolicitation.initial_state(uu)
    while true
        iter = iterate(uu, state)
        iter === nothing && break
        (i,t),state = iter
        s += t
    end
    s
end
```

This iterator will iterate at least once; it's important to check and exit early with a single threaded version.
"""
struct UnsignedIteratorEarlyStop{U}
    u::U
    i::UInt32
end
UnsignedIteratorEarlyStop(u) = UnsignedIteratorEarlyStop(u, count_ones(u) % UInt32)
UnsignedIteratorEarlyStop(u, i) = UnsignedIteratorEarlyStop(u, i % UInt32)

mask(u::UnsignedIteratorEarlyStop) = getfield(u, :u)
Base.IteratorSize(::Type{<:UnsignedIteratorEarlyStop}) = Base.HasShape{1}()
Base.IteratorEltype(::Type{<:UnsignedIteratorEarlyStop}) = Base.HasEltype()

Base.eltype(::UnsignedIteratorEarlyStop) = Tuple{UInt32,UInt32}
Base.length(u::UnsignedIteratorEarlyStop) = getfield(u, :i)
Base.size(u::UnsignedIteratorEarlyStop) = (getfield(u, :i),)

function initial_state(u::UnsignedIteratorEarlyStop)
    # LLVM should figure this out if you check?
    VectorizationBase.assume(0x00000000 ≠ u.i)
    (0x00000000,0x00000000,u.u)
end
@inline function Base.iterate(u::UnsignedIteratorEarlyStop, (i,j,uu) = initial_state(u))
    # VectorizationBase.assume(u.i ≤ 0x00000020)
    # VectorizationBase.assume(j ≤ count_ones(uu))
    # iszero(j) && return nothing
    j == u.i && return nothing
    VectorizationBase.assume(uu ≠ zero(uu))
    j += 0x00000001
    tz = trailing_zeros(uu) % UInt32
    tz += 0x00000001
    i += tz
    uu >>>= tz
    ((j,i), (i,j,uu))
end
function Base.show(io::IO, u::UnsignedIteratorEarlyStop)
    l = length(u)
    s = Vector{Int32}(undef, l)
    if l > 0
        s .= last.(u)
    end
    print("Thread ($l) Iterator: U", s)
end

# @inline function Base.iterate(u::UnsignedIteratorEarlyStop, (i,uu) = (0xffffffff,u.u))
#     tz = trailing_zeros(uu) % UInt32
#     tz == 0x00000020 && return nothing
#     tz += 0x00000001
#     i += tz
#     uu >>>= tz
#     (i, (i,uu))
# end

