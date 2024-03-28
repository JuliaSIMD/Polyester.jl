# S is a Val{Bool} indicating whether we will need to load the thread index
# C is a Tuple{...} containing the types of the reduction variables
struct BatchClosure{F,A,S,C}
  f::F
end
function (b::BatchClosure{F,A,S,C})(p::Ptr{UInt}) where {F,A,S,C}
  (offset, args) = ThreadingUtilities.load(p, A, 2 * sizeof(UInt))
  (offset, start) = ThreadingUtilities.load(p, UInt, offset)
  (offset, stop) = ThreadingUtilities.load(p, UInt, offset)
  if C === Tuple{} && !S
    b.f(args, (start + one(UInt)) % Int, stop % Int)
  elseif C === Tuple{} && S
    ((offset, i) = ThreadingUtilities.load(p, UInt, offset))
    b.f(args, (start + one(UInt)) % Int, stop % Int, i % Int)
  elseif C !== Tuple{} && !S
    ((offset, reducinits) = ThreadingUtilities.load(p, C, offset))
    reducres = b.f(args, (start + one(UInt)) % Int, stop % Int, reducinits)
    ThreadingUtilities.store!(p, reducres, offset)
  else
    ((offset, i) = ThreadingUtilities.load(p, UInt, offset))
    ((offset, reducinits) = ThreadingUtilities.load(p, C, offset))
    reducres = b.f(args, (start + one(UInt)) % Int, stop % Int, i % Int, reducinits)
    ThreadingUtilities.store!(p, reducres, offset)
  end
  ThreadingUtilities._atomic_store!(p, ThreadingUtilities.SPIN)
  nothing
end

@generated function batch_closure(f::F, args::A, ::Val{S}, reducinits::C) where {F,A,S,C}
  q = if Base.issingletontype(F)
    bc = BatchClosure{F,A,S,C}(F.instance)
    :(@cfunction($bc, Cvoid, (Ptr{UInt},)))
  else
    quote
      bc = BatchClosure{F,A,S,C}(f)
      @cfunction($(Expr(:$, :bc)), Cvoid, (Ptr{UInt},))
    end
  end
  return Expr(:block, Expr(:meta, :inline), q)
end
# @inline function batch_closure(f::F, args::A, ::Val{C}) where {F,A,C}
#   bc = BatchClosure{F,A,C}(f)
#   @cfunction($bc, Cvoid, (Ptr{UInt},))
# end

@inline function load_threadlocals(tid, argtup::A, ::Val{S}, reductup::C) where {A,S,C}
  p = ThreadingUtilities.taskpointer(tid)
  (offset, _) = ThreadingUtilities.load(p, UInt, sizeof(UInt))
  (offset, _) = ThreadingUtilities.load(p, A, offset)
  (offset, _) = ThreadingUtilities.load(p, UInt, offset)
  (offset, _) = ThreadingUtilities.load(p, UInt, offset)
  if S
    (offset, _) = ThreadingUtilities.load(p, UInt, offset)
  end
  (offset, _) = ThreadingUtilities.load(p, C, offset)
  (offset, reducvals) = ThreadingUtilities.load(p, C, offset)
  return reducvals
end

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
  i_or_reductup,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  offset = ThreadingUtilities.store!(p, i_or_reductup, offset)
  nothing
end
@inline function setup_batch!(
  p::Ptr{UInt},
  fptr::Ptr{Cvoid},
  argtup,
  start::UInt,
  stop::UInt,
  i::UInt,
  reductup,
)
  offset = ThreadingUtilities.store!(p, fptr, sizeof(UInt))
  offset = ThreadingUtilities.store!(p, argtup, offset)
  offset = ThreadingUtilities.store!(p, start, offset)
  offset = ThreadingUtilities.store!(p, stop, offset)
  offset = ThreadingUtilities.store!(p, i, offset)
  offset = ThreadingUtilities.store!(p, reductup, offset)
  nothing
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(tid, fptr, argtup, start, stop) do p, fptr, argtup, start, stop
    setup_batch!(p, fptr, argtup, start, stop)
  end
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop, i_or_reductup)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(
    tid,
    fptr,
    argtup,
    start,
    stop,
    i_or_reductup,
  ) do p, fptr, argtup, start, stop, i_or_reductup
    setup_batch!(p, fptr, argtup, start, stop, i_or_reductup)
  end
end
@inline function launch_batched_thread!(cfunc, tid, argtup, start, stop, i, reductup)
  fptr = Base.unsafe_convert(Ptr{Cvoid}, cfunc)
  ThreadingUtilities.launch(
    tid,
    fptr,
    argtup,
    start,
    stop,
    i,
    reductup,
  ) do p, fptr, argtup, start, stop, i, reductup
    setup_batch!(p, fptr, argtup, start, stop, i, reductup)
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
  needtid::Val{S},
  reducops::Tuple{Vararg{Any,C}},
  reducinits::Tuple{Vararg{Any,C}},
  threadmask_tuple::NTuple{N},
  nthread_tuple,
  torelease_tuple,
  Nr::Int,
  Nd,
  ulen,
  args::Vararg{Any,K},
) where {F,K,N,S,C}
  q = quote
    $(Expr(:meta, :inline))
    # threads = UnsignedIteratorEarlyStop(threadmask, nthread)
    # threads_tuple = map(UnsignedIteratorEarlyStop, threadmask_tuple, nthread_tuple)
    # nthread_total = sum(nthread_tuple)
    Ndp = Nd + one(Nd)
  end
  C !== 0 && push!(q.args, quote
    @nexprs $C j -> RVAR_j = reducinits[j]
  end)
  launch_quote = if S
    if C === 0
      :(launch_batched_thread!(cfunc, tid, argtup, start, stop, tid % UInt))
    else
      :(launch_batched_thread!(cfunc, tid, argtup, start, stop, tid % UInt, reducinits))
    end
  else
    if C === 0
      :(launch_batched_thread!(cfunc, tid, argtup, start, stop))
    else
      :(launch_batched_thread!(cfunc, tid, argtup, start, stop, reducinits))
    end
  end
  f_quote = Expr(:call, :f!, :arguments, :((start + one(UInt)) % Int), :(ulen % Int))
  S && push!(f_quote.args, :((sum(nthread_tuple) + 1) % Int))
  C !== 0 && push!(f_quote.args, :reducinits)
  rem_quote = Expr(:block, :(thread_results = $f_quote))
  if C !== 0
    push!(
      rem_quote.args,
      :(@nexprs $C j -> RVAR_j = reducops[j](RVAR_j, thread_results[j])),
    )
  end
  update_retv = if C === 0
    Expr(:block)
  else
    quote
      thread_results = load_threadlocals(tid, argtup, needtid, reducinits)
      @nexprs $C j -> RVAR_j = reducops[j](RVAR_j, thread_results[j])
    end
  end
  ret_quote = Expr(:return)
  redtup = Expr(:tuple)
  for j ∈ 1:C
    push!(redtup.args, Symbol("RVAR_", j))
  end
  push!(ret_quote.args, redtup)

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
        $update_retv
      end
    end
    free_threads!(torelease_tuple)
    $ret_quote
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
    :(cfunc = batch_closure(f!, argtup, Val{$S}(), reducinits)),
    gcpr,
  )
  q
end

@inline function batch(
  f!::F,
  (len, nbatches)::Tuple{Vararg{Union{StaticInt,Integer},2}},
  args::Vararg{Any,K},
) where {F,K}

  batch(f!, Val{false}(), (), (), (len, nbatches), args...)
end

@inline function batch(
  f!::F,
  needtid::Val{S},
  reducops::Tuple{Vararg{Any,C}},
  reducinits::Tuple{Vararg{Any,C}},
  (len, nbatches)::Tuple{Vararg{Union{StaticInt,Integer},2}},
  args::Vararg{Any,K},
) where {F,K,C,S}
  len > 0 || return reducinits
  for var in reducinits
    @assert isbits(var)
  end
  if (nbatches > len)
    if (typeof(nbatches) !== typeof(len))
      return batch(f!, reducops, reducinits, needtid, (len, len), args...)
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
    if S
      if C === 0
        f!(args, one(Int), ulen % Int, 1)
        return ()
      else
        reducres = f!(args, one(Int), ulen % Int, 1, reducinits)
        return reducres
      end
    else
      if C === 0
        f!(args, one(Int), ulen % Int)
        return ()
      else
        reducres = f!(args, one(Int), ulen % Int, reducinits)
        return reducres
      end
    end
  end
  nbatch = nthread + one(nthread)
  Nd = Base.udiv_int(ulen, nbatch % UInt) # reasonable for `ulen` to be ≥ 2^32
  Nr = (ulen - Nd * nbatch) % Int
  _batch_no_reserve(
    f!,
    needtid,
    reducops,
    reducinits,
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
  needtid::Val{S} = Val(false),
  reducops::Tuple{Vararg{Any,C}} = (),
  reducinits::Tuple{Vararg{Any,C}} = (),
) where {F,K,C,S}
  batch(f!, needtid, reducops, reducinits, (len, nbatches), args...)
end
