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
reset_workers!() = WORKERS[] = UInt128((1 << (Threads.nthreads() - 1)) - 1)
function __init__()
    reset_workers!()
    resize!(STATES, num_threads() * cache_linesize())
    STATES .= 0x00
    @require ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210" include("forwarddiff.jl")
end

end
