module Polyester
if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@max_methods"))
  @eval Base.Experimental.@max_methods 1
end

using ThreadingUtilities
import StaticArrayInterface
const ArrayInterface = StaticArrayInterface
using StaticArrayInterface: static_length, static_step, static_first, static_size
using StrideArraysCore: object_and_preserve
using ManualMemory: Reference
using Static
using Requires
using PolyesterWeave:
  PolyesterWeave,
  request_threads,
  free_threads!,
  mask,
  UnsignedIteratorEarlyStop,
  assume,
  disable_polyester_threads
using CPUSummary: num_cores

export batch, @batch, disable_polyester_threads

include("batch.jl")
include("closure.jl")


# see https://github.com/JuliaSIMD/Polyester.jl/issues/30
"""
    Polyester.reset_threads!()

Resets the threads used by [Polyester.jl](https://github.com/JuliaSIMD/Polyester.jl).
"""
function reset_threads!()
  PolyesterWeave.reset_workers!()
  foreach(ThreadingUtilities.checktask,
          eachindex(ThreadingUtilities.TASKS))
  return nothing
end

# y = rand(1)
# x = rand(1)
# @batch for i ∈ eachindex(y,x)
#   y[i] = sin(x[i])
# end
end
