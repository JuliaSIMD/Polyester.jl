struct BatchClosure{F,A,C} # C is a Val{Bool} triggering local storage
  f::F
end
function (b::BatchClosure{F,A,C})(p::Ptr{UInt}) where {F,A,C}
  (offset, args) = ThreadingUtilities.load(p, A, 2 * sizeof(UInt))
  (offset, start) = ThreadingUtilities.load(p, UInt, offset)
  (offset, stop) = ThreadingUtilities.load(p, UInt, offset)
  if C
    ((offset, i) = ThreadingUtilities.load(p, UInt, offset))
    b.f(args, (start + one(UInt)) % Int, stop % Int, i % Int)
  else
    b.f(args, (start + one(UInt)) % Int, stop % Int)
  end
  ThreadingUtilities._atomic_store!(p, ThreadingUtilities.SPIN)
  nothing
end

@generated function batch_closure(f::F, args::A, ::Val{C}) where {F,A,C}
  q = if Base.issingletontype(F)
    bc = BatchClosure{F,A,C}(F.instance)
    :(@cfunction($bc, Cvoid, (Ptr{UInt},)))
  else
    quote
      bc = BatchClosure{F,A,C}(f)
      @cfunction($(Expr(:$, :bc)), Cvoid, (Ptr{UInt},))
    end
  end
  return Expr(:block, Expr(:meta, :inline), q)
end
# @inline function batch_closure(f::F, args::A, ::Val{C}) where {F,A,C}
#   bc = BatchClosure{F,A,C}(f)
#   @cfunction($bc, Cvoid, (Ptr{UInt},))
# end

@inline function setup_batch!(
  p::Ptr{UInt},
  fptr::Ptr{Cvoid},
  argtup,
  start::UInt,
  stop::UInt,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  nothing
end
@inline function setup_batch!(
  p::Ptr{UInt},
  fptr::Ptr{Cvoid},
  argtup,
  start::UInt,
  stop::UInt,
  i::UInt,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  offset = ThreadingUtilities.store!(p, i, offset)
  nothing
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(tid, fptr, argtup, start, stop) do p, fptr, argtup, start, stop
    setup_batch!(p, fptr, argtup, start, stop)
  end
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop, i)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(
    tid,
    fptr,
    argtup,
    start,
    stop,
    i,
  ) do p, fptr, argtup, start, stop, i
    setup_batch!(p, fptr, argtup, start, stop, i)
  end
end
_extract_params(::Type{T}) where {T<:Tuple} = T.parameters
_extract_params(::Type{NamedTuple{S,T}}) where {S,T<:Tuple} = T.parameters
push_tup!(x, ::Type{T}, t) where {T<:Tuple} = push!(x, t)
push_tup!(x, ::Type{NamedTuple{S,T}}, t) where {S,T<:Tuple} =
  push!(x, Expr(:call, Expr(:curly, :NamedTuple, S), t))

function add_var!(q, argtup, gcpres, ::Type{T}, argtupname, gcpresname, k) where {T}
  parg_k = Symbol(argtupname, :_, k)
  garg_k = Symbol(gcpresname, :_, k)
  if (T <: Tuple) # || (T <: NamedTuple) # NamedTuples do currently not work in all cases, see https://github.com/JuliaSIMD/Polyester.jl/issues/20
    push!(q.args, Expr(:(=), parg_k, Expr(:ref, argtupname, k)))
    t = Expr(:tuple)
    for (j, p) ∈ enumerate(_extract_params(T))
      add_var!(q, t, gcpres, p, parg_k, garg_k, j)
    end
    push_tup!(argtup.args, T, t)
  else
    push!(
      q.args,
      Expr(
        :(=),
        Expr(:tuple, parg_k, garg_k),
        Expr(:call, :object_and_preserve, Expr(:ref, argtupname, k)),
      ),
    )
    push!(argtup.args, parg_k)
    push!(gcpres.args, garg_k)
  end
end
@generated function _batch_no_reserve(
  f!::F,
  threadlocal::Val{thread_local},
  threadmask_tuple::NTuple{N},
  nthread_tuple,
  torelease_tuple,
  Nr::Int,
  Nd,
  ulen,
  args::Vararg{Any,K},
) where {F,K,N,thread_local}
  q = quote
    $(Expr(:meta, :inline))
    # threads = UnsignedIteratorEarlyStop(threadmask, nthread)
    # threads_tuple = map(UnsignedIteratorEarlyStop, threadmask_tuple, nthread_tuple)
    # nthread_total = sum(nthread_tuple)
    Ndp = Nd + one(Nd)
  end
  launch_quote = if thread_local
    :(launch_batched_thread!(cfunc, tid, argtup, start, stop, i % UInt))
  else
    :(launch_batched_thread!(cfunc, tid, argtup, start, stop))
  end
  rem_quote = if thread_local
    :(f!(arguments, (start + one(UInt)) % Int, ulen % Int, (sum(nthread_tuple) + 1) % Int))
  else
    :(f!(arguments, (start + one(UInt)) % Int, ulen % Int))
  end
  block = quote
    start = zero(UInt)
    tid = 0x00000000
    for (threadmask, nthread) ∈ zip(threadmask_tuple, nthread_tuple)
      tm = mask(UnsignedIteratorEarlyStop(threadmask, nthread))
      i = 0x00000000
      while i ≠ nthread
        assume(tm ≠ zero(tm))
        tz = trailing_zeros(tm) % UInt32
        stop = start + ifelse(i < Nr, Ndp, Nd)
        i += 0x00000001
        tz += 0x00000001
        tid += tz
        tm >>>= tz
        $launch_quote
        start = stop
      end
      Nr = (Nr - nthread) % Int
    end
    $rem_quote
    tid = 0x00000000
    for (threadmask, nthread) ∈ zip(threadmask_tuple, nthread_tuple)
      tm = mask(UnsignedIteratorEarlyStop(threadmask, nthread))
      while tm ≠ zero(tm)
        # assume(tm ≠ zero(tm)) 
        tz = trailing_zeros(tm) % UInt32
        tz += 0x00000001
        tm >>>= tz
        tid += tz
        # @show tid, ThreadingUtilities._atomic_state(tid)
        ThreadingUtilities.wait(tid)
      end
    end
    free_threads!(torelease_tuple)
    nothing
  end
  gcpr = Expr(:gc_preserve, block, :cfunc)
  argt = Expr(:tuple)
  for k ∈ 1:K
    add_var!(q, argt, gcpr, args[k], :args, :gcp, k)
  end
  push!(
    q.args,
    :(arguments = $argt),
    :(argtup = Reference(arguments)),
    :(cfunc = batch_closure(f!, argtup, Val{$thread_local}())),
    gcpr,
  )
  push!(q.args, nothing)
  q
end
# @generated function _batch_reserve(
#     f!::F, threadmask_tuple::Tuple{Vararg{Any,N}}, nthreads_tuple, torelease_tuple, nbatch, unused_threads, Nr, Nd, ulen, args::Vararg{Any,K}
# ) where {F,K,N}
#   q = quote
#     nthread_total = nbatch - one(nbatch)
#     nthread_denom = $(N == 1 ? 0 : :(sum(nthreads_tuple)))
#     Ndp = Nd + one(Nd)
#     nres_per = Base.udiv_int(unused_threads, nbatch)
#     nres_rem = unused_threads - nres_per * nbatch
#     nres_prr = nres_per + one(nres_per)
#     # nbatch_per_thread = 
#   end
#   nthread_expr = if N == 1
#     quote
#       nthread = nthread_total
#     end
#   else
#     quote
#       nthreads == zero(nthreads) && continue
#       nthread = max(1, (nthread_total * nthreads) ÷ nthread_denom)

#     end
#   end
#   break_cond = N == 1 ? :(i == nthread) : :((i == nthread) | (j == nthread_total))
#   block = quote
#     start = zero(UInt)
#     i = zero(nres_rem)
#     tid = 0x00000000
#     j = 0x00000000
#     for (threads, nthreads) ∈ zip(threadmask_tuple,nthreads_tuple)
#       $nthread_expr
#       threads = UnsignedIteratorEarlyStop(threadmask, nthread)
#       tm = mask(threads)
#       wait_mask = zero(worker_type())
#       while true
#         assume(tm ≠ zero(tm))
#         tz = trailing_zeros(tm) % UInt32
#         reserve = ifelse(i < nres_rem, nres_prr, nres_per)
#         tz += 0x00000001
#         stop = start + ifelse(i < Nr, Ndp, Nd)
#         tid += tz
#         tid_to_launch = tid
#         wait_mask |= (one(wait_mask) << (tid - one(tid)))
#         tm >>>= tz
#         reserved_threads = zero(worker_type())
#         for _ ∈ 1:reserve
#           assume(tm ≠ zero(tm))
#           tz = trailing_zeros(tm) % UInt32
#           tz += 0x00000001
#           tid += tz
#           tm >>>= tz
#           reserved_threads |= (one(reserved_threads) << (tid - one(tid)))
#         end
#         reserve_threads!(tid_to_launch, reserved_threads)
#         launch_batched_thread!(cfunc, tid_to_launch, argtup, start, stop)
#         i += one(i)
#         start = stop
#         $break_cond && break
#       end
#     end
#     reserved_threads = zero(worker_type())
#     for _ ∈ 1:nres_per
#       assume(tm ≠ zero(tm))
#       tz = trailing_zeros(tm) % UInt32
#       tz += 0x00000001
#       tid += tz
#       tm >>>= tz
#       reserved_threads |= (one(reserved_threads) << (tid - one(tid)))
#     end
#     reserve_threads!(0x00000000, reserved_threads)
#     f!(arguments, (start+one(UInt)) % Int, ulen % Int)
#     free_threads!(reserved_threads)
#     reserve_threads!(0x00000000, zero(worker_type()))
#     tid = 0x00000000
#     while true
#       assume(wait_mask ≠ zero(wait_mask))
#       tz = (trailing_zeros(wait_mask) % UInt32) + 0x00000001
#       wait_mask >>>= tz
#       tid += tz
#       ThreadingUtilities.wait(tid)
#       iszero(wait_mask) && break
#     end
#     nothing
#   end
#   gcpr = Expr(:gc_preserve, block, :cfunc)
#   argt = Expr(:tuple)
#   for k ∈ 1:K
#     add_var!(q, argt, gcpr, args[k], :args, :gcp, k)
#   end
#   push!(q.args, :(arguments = $argt), :(argtup = Reference(arguments)), :(cfunc = batch_closure(f!, argtup, Val{true}())), gcpr, :(free_local_threads!()))
#   push!(q.args, nothing)
#   q
# end

@inline function batch(
  f!::F,
  (len, nbatches)::Tuple{Vararg{Any,2}},
  args::Vararg{Any,K},
) where {F,K}

  batch(f!, Val{false}(), (len, nbatches), args...)
end

@inline function batch(
  f!::F,
  threadlocal::Val{thread_local},
  (len, nbatches)::Tuple{Vararg{Any,2}},
  args::Vararg{Any,K},
) where {F,K,thread_local}
  # threads, torelease = request_threads(Base.Threads.threadid(), nbatches - one(nbatches))
  len > 0 || return
  ulen = len % UInt
  nbatches == 0 && @goto SERIAL
  threads, torelease = request_threads(nbatches - one(nbatches))
  nthreads = map(length, threads)
  nthread = sum(nthreads)
  if nthread % Int32 ≤ zero(Int32)
    @label SERIAL
    if thread_local
      f!(args, one(Int), ulen % Int, 1)
    else
      f!(args, one(Int), ulen % Int)
    end
    return
  end
  nbatch = nthread + one(nthread)
  Nd = Base.udiv_int(ulen, nbatch % UInt) # reasonable for `ulen` to be ≥ 2^32
  Nr = (ulen - Nd * nbatch) % Int
  _batch_no_reserve(
    f!,
    threadlocal,
    map(mask, threads),
    nthreads,
    torelease,
    Nr,
    Nd,
    ulen,
    args...,
  )
end
function batch(
  f!::F,
  (len, nbatches, reserve_per_worker)::Tuple{Vararg{Any,3}},
  args::Vararg{Any,K};
  threadlocal::Val{thread_local} = Val(false),
) where {F,K,thread_local}
  batch(f!, (len, nbatches), args...; threadlocal)
  # ulen = len % UInt
  # if nbatches > 1
  #   requested_threads = reserve_per_worker*nbatches
  #   threads, torelease = request_threads(Base.Threads.threadid(), requested_threads - one(nbatches))
  #   nthreads = map(length, threads)
  #   nthread = sum(nthreads)
  #   if nthread % Int32 > zero(Int32)
  #     total_threads = nthread + one(nthread)
  #     nbatch = min(total_threads % UInt32, nbatches % UInt32)

  #     Nd = Base.udiv_int(ulen, nbatch % UInt)
  #     Nr = ulen - Nd * nbatch

  #     unused_threads = total_threads - nbatch
  #     threadmasks = map(mask,threads)
  #     if iszero(unused_threads)
  #       _batch_no_reserve(f!, threadmasks, nthreads, torelease, Nr, Nd, ulen, args...)
  #     else

  #       _batch_reserve(f!, threadmasks, nthreads, torelease, nbatch, unused_threads, Nr, Nd, ulen, args...)
  #     end
  #     return nothing
  #   end
  # end
  # f!(args, one(Int), ulen%Int)
  # return nothing
end
