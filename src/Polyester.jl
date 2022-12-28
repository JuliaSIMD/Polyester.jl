module Polyester

using ThreadingUtilities
import ArrayInterface
using ArrayInterface: static_length, static_step, static_first, size
using StrideArraysCore: object_and_preserve
using ManualMemory: Reference
using Static
using Requires
using PolyesterWeave:
  request_threads, free_threads!, mask, UnsignedIteratorEarlyStop, assume,
  disable_polyester_threads,
  num_threads # used to be taken from CPUSummary, but it caused significant TTFX | TODO remove on next breaking release and consider removing num_cores
using CPUSummary: num_cores

export batch, @batch, num_threads, disable_polyester_threads

include("batch.jl")
include("closure.jl")

# y = rand(1)
# x = rand(1)
# @batch for i ∈ eachindex(y,x)
#   y[i] = sin(x[i])
# end
end
