function worker_bits()
  ws = nextpow2(num_threads())
  IfElse.ifelse(Static.lt(ws,StaticInt{8}()), StaticInt{8}(), ws)
end
function worker_mask_count()
  bits = worker_bits()
  (bits + StaticInt{63}()) ÷ StaticInt{64}() # cld not defined on `StaticInt`
end
worker_size() = worker_bits() ÷ worker_mask_count()

# _worker_type_combined(::StaticInt{1}) = worker_type()
# _worker_type_combined(::StaticInt{M}) where {M} = NTuple{M,worker_type()}
# worker_type_combined() = _worker_type_combined(worker_mask_count())

_mask_type(::StaticInt{8}) = UInt8
_mask_type(::StaticInt{16}) = UInt16
_mask_type(::StaticInt{32}) = UInt32
_mask_type(::StaticInt{64}) = UInt64
worker_type() = _mask_type(worker_size())
worker_pointer_type() = Ptr{worker_type()}

const WORKERS = Ref(zero(UInt128)) # 0 = unavailable, 1 = available
const STATES = UInt8[]

worker_pointer() = Base.unsafe_convert(worker_pointer_type(), pointer_from_objref(WORKERS))


@inline _reserved(p, ::StaticInt{N}) where {N} = (unsafe_load(p), _reserved(p+8, StaticInt{N}() - StaticInt{1}())...)
@inline _reserved(p, ::StaticInt{1}) = (unsafe_load(p),)
@inline reserved(id) = _reserved(Base.unsafe_convert(worker_pointer_type(), STATES) + (cache_linesize() * id), worker_mask_count())

function reserve_threads!(id, reserve::Unsigned)
  p = Base.unsafe_convert(worker_pointer_type(), STATES)
  unsafe_store!(p + (cache_linesize() * id), reserve % worker_type())
  nothing
end
function free_threads!(freed_threads)
  ThreadingUtilities._atomic_or!(worker_pointer(), freed_threads)
  nothing
end
function free_local_threads!()
  tid = Base.Threads.threadid()
  tid -= one(tid)
  tmask = one(worker_type()) << (tid - one(tid))
  r = reserved(tid) | tmask
  reserve_threads!(tid, zero(worker_type()))
  free_threads!(r)
end

_request_threads(num_requested::UInt32, wp::Ptr, reserved::Tuple{}) = (), ()
@inline function _request_threads(num_requested::UInt32, wp::Ptr, reserved::NTuple)
  ui, ft, num_requested, wp = __request_threads(num_requested, wp, first(reserved))
  uit, ftt = _request_threads(num_requested, wp, Base.tail(reserved))
  (ui, uit...), (ft, ftt...)
end
@inline function __request_threads(num_requested::UInt32, wp::Ptr, reserved_threads)
  no_threads = zero(worker_type())
  if num_requested % Int32 ≤ zero(Int32)
    return UnsignedIteratorEarlyStop(zero(worker_type()), 0x00000000), no_threads, 0x00000000, wp
  end
  reserved_count = count_ones(reserved_threads)%UInt32
  # reserved_count ≥ num_requested && return reserved_threads, no_threads
  if reserved_count%Int32 ≥ num_requested%Int32
    return UnsignedIteratorEarlyStop(reserved_threads, num_requested), no_threads, num_requested - reserved_count, wp
  end
  # to get more, we xchng, setting all to `0`
  # then see which we need, and free those we aren't using.
  wpret = wp + 8 # (worker_type() === UInt64) | (worker_mask_count() === StaticInt(1)) #, so adding 8 is fine.
  _all_threads = all_threads = ThreadingUtilities._atomic_xchg!(wp, no_threads)
  additional_threads = count_ones(all_threads) % UInt32
  # num_requested === StaticInt{-1}() && return reserved_threads, all_threads
  if num_requested === StaticInt{-1}()
    return UnsignedIteratorEarlyStop(reserved_threads | all_threads), all_threads, num_requested, wpret
  end
  nexcess = num_requested - additional_threads - reserved_count
  # signed(excess) ≤ 0 && return reserved_threads, all_threads
  if signed(nexcess) ≥ 0
    return UnsignedIteratorEarlyStop(reserved_threads | all_threads), all_threads, nexcess, wpret
  end
  # we need to return the `excess` to the pool.
  lz = leading_zeros(all_threads) % UInt32
  # i = 16
  while true
    # start by trying to trim off excess from lz
    lz += (-nexcess)%UInt32
    m = (one(worker_type()) << (UInt32(last(worker_size())) - lz)) - one(worker_type())
    masked = (all_threads & m) ⊻ all_threads
    nexcess += count_ones(masked) % UInt32
    all_threads &= (~masked)
    nexcess == zero(nexcess) && break
    # i -= 1
    # @assert i > 0
  end
  ThreadingUtilities._atomic_store!(wp, _all_threads & (~all_threads))
  return UnsignedIteratorEarlyStop(reserved_threads | all_threads, num_requested), all_threads, 0x00000000, wpret
end
@inline function request_threads(id, num_requested)
  _request_threads(num_requested % UInt32, worker_pointer(), reserved(id % UInt32))
end
reserved_threads(id) = UnsignedIteratorEarlyStop(reserved(id))
reserved_threads(id, count) = UnsignedIteratorEarlyStop(reserved(id), count % UInt32)



