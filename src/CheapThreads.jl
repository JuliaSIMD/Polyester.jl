module CheapThreads

using ThreadingUtilities, VectorizationBase
using VectorizationBase: num_threads, cache_linesize, __vload, __vstore!, register_size, False
using StrideArraysCore: object_and_preserve, dereference
using Requires

export batch, num_threads


include("request.jl")
include("batch.jl")
include("unsignediterator.jl")

# reset_workers!() = WORKERS[] = UInt128((1 << (num_threads() - 1)) - 1)
dynamic_thread_count() = min((Sys.CPU_THREADS)::Int, Threads.nthreads())
reset_workers!() = WORKERS[] = UInt128((1 << (dynamic_thread_count() - 1)) - 1)
function __init__()
    reset_workers!()
    resize!(STATES, dynamic_thread_count() * cache_linesize())
    STATES .= 0x00
    @require ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210" include("forwarddiff.jl")
end

end
