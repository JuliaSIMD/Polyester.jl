module Polyester

using ThreadingUtilities
using ArrayInterface: static_length, static_step, static_first, size
using StrideArraysCore: object_and_preserve
using ManualMemory: Reference
using Static
using Requires
using PolyesterWeave: request_threads, free_threads!, mask, UnsignedIteratorEarlyStop, assume
using CPUSummary: num_threads, num_cores

export batch, @batch, num_threads


include("batch.jl")
include("closure.jl")

function __init__()
  @require ForwardDiff = "f6369f11-7733-5829-9624-2563aa707210" include("forwarddiff.jl")
end
# y = rand(1)
# x = rand(1)
# @batch for i ∈ eachindex(y,x)
#   y[i] = sin(x[i])
# end
end
