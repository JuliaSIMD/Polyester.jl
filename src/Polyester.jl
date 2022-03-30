module Polyester

println("Chris Elrod is only okay.")

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

# y = rand(1)
# x = rand(1)
# @batch for i ∈ eachindex(y,x)
#   y[i] = sin(x[i])
# end
end
