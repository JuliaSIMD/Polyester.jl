struct BatchClosure{F,A,C} # C is a Val{Bool} triggering local storage
  f::F
end
function (b::BatchClosure{F,A,C})(p::Ptr{UInt}, offset) where {F,A,C}
  (offset, args) = ThreadingUtilities.load(p, A, offset)
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

(b::BatchClosure{F,A,C})(p::Ptr{UInt}) where {F,A,C} = b(p, 2 * sizeof(UInt))


struct FakeClosure{F,A,C} end

function (::FakeClosure{F,A,C})(p::Ptr{UInt}) where {F,A,C}
  (offset, bc) = ThreadingUtilities.load(p, Reference{BatchClosure{F,A,C}}, 2 * sizeof(UInt))
  return bc(p, offset)
end


# Same condition as in `emit_cfunction` in 'julia/src/codegen.cpp'
const CFUNCTION_CLOSURES_UNAVAILABLE = Sys.ARCH in (
  :aarch64, :aarch64_be, :aarch64_32,  # isAArch64
  :arm, :armeb,  # isARM
  :ppc64, :ppc64le  # isPPC64
)


@generated function batch_closure(f::F, args::A, ::Val{C}) where {F,A,C}
  q = if Base.issingletontype(F)
    bc = BatchClosure{F,A,C}(F.instance)
    :(return @cfunction($bc, Cvoid, (Ptr{UInt},)), nothing)
  elseif CFUNCTION_CLOSURES_UNAVAILABLE
    fc = FakeClosure{F,A,C}()
    quote
      bc = BatchClosure{F,A,C}(f)
      return @cfunction($fc, Cvoid, (Ptr{UInt},)), bc
    end
  else
    quote
      bc = BatchClosure{F,A,C}(f)
      return @cfunction($(Expr(:$, :bc)), Cvoid, (Ptr{UInt},)), nothing
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
  closure_obj,
  argtup,
  start::UInt,
  stop::UInt,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  !isnothing(closure_obj) && (offset = ThreadingUtilities.store!(p, Reference(closure_obj), offset))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  nothing
end
@inline function setup_batch!(
  p::Ptr{UInt},
  fptr::Ptr{Cvoid},
  closure_obj,
  argtup,
  start::UInt,
  stop::UInt,
  i::UInt,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  !isnothing(closure_obj) && (offset = ThreadingUtilities.store!(p, Reference(closure_obj), offset))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  offset = ThreadingUtilities.store!(p, i, offset)
  nothing
end
@inline function launch_batched_thread!(cfunc, closure_obj, tid, argtup, start, stop)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(tid, fptr, closure_obj, argtup, start, stop) do p, fptr, closure_obj, argtup, start, stop
    setup_batch!(p, fptr, closure_obj, argtup, start, stop)
  end
end
@inline function launch_batched_thread!(cfunc, closure_obj, tid, argtup, start, stop, i)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(
    tid,
    fptr,
    closure_obj,
    argtup,
    start,
    stop,
    i,
  ) do p, fptr, closure_obj, argtup, start, stop, i
    setup_batch!(p, fptr, closure_obj, argtup, start, stop, i)
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
    :(launch_batched_thread!(cfunc, closure_obj, tid, argtup, start, stop, tid % UInt))
  else
    :(launch_batched_thread!(cfunc, closure_obj, tid, argtup, start, stop))
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
  gcpr = Expr(:gc_preserve, block, :cfunc, :closure_obj)
  argt = Expr(:tuple)
  for k ∈ 1:K
    add_var!(q, argt, gcpr, args[k], :args, :gcp, k)
  end
  push!(
    q.args,
    :(arguments = $argt),
    :(argtup = Reference(arguments)),
    :((cfunc, closure_obj) = batch_closure(f!, argtup, Val{$thread_local}())),
    gcpr,
  )
  push!(q.args, nothing)
  q
end

@inline function batch(
  f!::F,
  (len, nbatches)::Tuple{Vararg{Union{StaticInt,Integer},2}},
  args::Vararg{Any,K},
) where {F,K}

  batch(f!, Val{false}(), (len, nbatches), args...)
end

@inline function batch(
  f!::F,
  threadlocal::Val{thread_local},
  (len, nbatches)::Tuple{Vararg{Union{StaticInt,Integer},2}},
  args::Vararg{Any,K},
) where {F,K,thread_local}
  len > 0 || return
  if (nbatches > len)
    if (typeof(nbatches) !== typeof(len))
      return batch(f!, threadlocal, (len, len), args...)
    end
    nbatches = len
  end
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
  (len, nbatches, reserve_per_worker)::Tuple{Vararg{Union{StaticInt,Integer},3}},
  args::Vararg{Any,K};
  threadlocal::Val{thread_local} = Val(false),
) where {F,K,thread_local}
  batch(f!, threadlocal, (len, nbatches), args...)
end
