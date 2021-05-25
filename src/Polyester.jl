module Polyester

using ThreadingUtilities, VectorizationBase
using ArrayInterface: static_length, static_step, static_first, size
using VectorizationBase: num_threads, num_cores, cache_linesize, __vload, __vstore!, register_size, False
using StrideArraysCore: object_and_preserve, dereference
import IfElse
using Static
using Requires

export batch, @batch, num_threads


include("request.jl")
include("batch.jl")
include("closure.jl")
include("unsignediterator.jl")

# reset_workers!() = WORKERS[] = UInt128((1 << (num_threads() - 1)) - 1)
dynamic_thread_count() = min((Sys.CPU_THREADS)::Int, Threads.nthreads())
reset_workers!() = WORKERS[] = (one(UInt128) << (dynamic_thread_count() - one(UInt128))) - one(UInt128)
function __init__()
    reset_workers!()
    resize!(STATES, dynamic_thread_count() * cache_linesize())
    STATES .= 0x00
    @require ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210" include("forwarddiff.jl")
end

end
