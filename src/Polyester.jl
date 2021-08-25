module Polyester

using ThreadingUtilities
using ArrayInterface: static_length, static_step, static_first, size
using CPUSummary: num_threads, num_cores, cache_linesize
using StrideArraysCore: object_and_preserve
using ManualMemory: Reference
import IfElse
using Static
using Requires
using BitTwiddlingConvenienceFunctions: nextpow2

export batch, @batch, num_threads

@static if VERSION ≥ v"1.6.0-DEV.674"
  @inline function assume(b::Bool)
    Base.llvmcall(("""
      declare void @llvm.assume(i1)

      define void @entry(i8 %byte) alwaysinline {
      top:
        %bit = trunc i8 %byte to i1
        call void @llvm.assume(i1 %bit)
        ret void
      }
  """, "entry"), Cvoid, Tuple{Bool}, b)
  end
else
  @inline assume(b::Bool) = Base.llvmcall(("declare void @llvm.assume(i1)", "%b = trunc i8 %0 to i1\ncall void @llvm.assume(i1 %b)\nret void"), Cvoid, Tuple{Bool}, b)
end

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

# y = rand(1)
# x = rand(1)
# @batch for i ∈ eachindex(y,x)
#   y[i] = sin(x[i])
# end
end
