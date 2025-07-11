module Polyester
if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@max_methods"))
  @eval Base.Experimental.@max_methods 1
end

using ThreadingUtilities
import StaticArrayInterface
const ArrayInterface = StaticArrayInterface
using Base.Cartesian: @nexprs
using StaticArrayInterface: static_length, static_step, static_first, static_size
using StrideArraysCore: object_and_preserve
using ManualMemory: Reference
using Static
using PolyesterWeave:
  PolyesterWeave,
  request_threads,
  free_threads!,
  mask,
  UnsignedIteratorEarlyStop,
  assume,
  disable_polyester_threads

export batch, @batch, disable_polyester_threads

const SUPPORTED_REDUCE_OPS = (:+, :*, :min, :max, :&, :|)
initializer(::typeof(+), ::T) where {T} = zero(T)
initializer(::typeof(+), ::Bool) = zero(Int)
initializer(::typeof(*), ::T) where {T} = one(T)
initializer(::typeof(min), ::T) where {T} = typemax(T)
initializer(::typeof(max), ::T) where {T} = typemin(T)
initializer(::typeof(&), ::Bool) = true
initializer(::typeof(|), ::Bool) = false

include("batch.jl")
include("closure.jl")


# see https://github.com/JuliaSIMD/Polyester.jl/issues/30
"""
    Polyester.reset_threads!()

Resets the threads used by [Polyester.jl](https://github.com/JuliaSIMD/Polyester.jl).
"""
function reset_threads!()
  PolyesterWeave.reset_workers!()
  foreach(ThreadingUtilities.reinit_task, eachindex(ThreadingUtilities.TASKS))
  return nothing
end
end
