# Polyester

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSIMD.github.io/Polyester.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSIMD.github.io/Polyester.jl/dev)
[![CI](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI.yml)
[![CI-Nightly](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI-julia-nightly.yml/badge.svg)](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI-julia-nightly.yml)
[![Coverage](https://codecov.io/gh/JuliaSIMD/Polyester.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaSIMD/Polyester.jl)

Polyester.jl provides **low-overhead multithreading** in Julia. The primary API is `@batch`, which can be used to parallelize for-loops (similar to `@threads`).

Polyester implements static scheduling (c.f. `@threads :static`) and has minimal overhead because it manages and re-uses a dedicated set of Julia tasks. This can lead to (great) speedups compared to other multithreading variants (see [Benchmark]() below).

## Basic usage example

```julia
using Polyester

function axpy_polyester!(y, a, x)
    @batch for i in eachindex(y,x)
        y[i] = a * x[i] + y[i]
    end
end

a = 3.141
x = rand(10_000)
y = rand(10_000)
axpy_polyester!(y, a, x)
```

## Important Notes

* `Polyester.@batch` moves arrays to threads by turning them into [StrideArraysCore.PtrArray](https://github.com/JuliaSIMD/StrideArraysCore.jl)s. This means that under an `@batch` slices will create `view`s by default(!). You may want to start Julia with `--check-bounds=yes` while debugging.

* Polyester uses the regular Julia threads. The total number of threads is still governed by [`--threads` or `JULIA_NUM_THREADS`](https://docs.julialang.org/en/v1.6/manual/multi-threading/#Starting-Julia-with-multiple-threads) (check with `Threads.nthreads()`).

* Polyester **does not** pin Julia threads to CPU-cores/threads. You can control how many "Polyester tasks" you want to use (see below). But to ensure that these tasks are running on specific CPU-cores/threads, you need to use a tool like [ThreadPinning.jl](https://github.com/carstenbauer/ThreadPinning.jl).

## Simple benchmark

Let's consider a basic [axpy](https://en.wikipedia.org/wiki/Basic_Linear_Algebra_Subprograms#Level_1) kernel.

```julia
using Polyester: @batch
using Base.Threads: @threads
using LinearAlgebra
using BenchmarkTools

# pinning threads for good measure
using ThreadPinning
pinthreads(:cores)

# Single threaded.
function axpy_serial!(y, a, x)
    for i in eachindex(y,x)
        @inbounds y[i] = a * x[i] + y[i]
    end
end

# Multithreaded with @batch
function axpy_batch!(y, a, x)
    @batch for i in eachindex(y,x)
        @inbounds y[i] = a * x[i] + y[i]
    end
end

# Multithreaded with @threads (default scheduling)
function axpy_atthreads!(y, a, x)
    @threads for i in eachindex(y,x)
        @inbounds y[i] = a * x[i] + y[i]
    end
end

# Multithreaded with @threads :static
function axpy_atthreads_static!(y, a, x)
    @threads :static for i in eachindex(y,x)
        @inbounds y[i] = a * x[i] + y[i]
    end
end

y = rand(10_000);
x = rand(10_000);
@benchmark axpy_serial!($y, eps(), $x)
@benchmark axpy_batch!($y, eps(), $x)
@benchmark axpy_atthreads!($y, eps(), $x)
@benchmark axpy_atthreads_static!($y, eps(), $x)
@benchmark axpy!(eps(), $x, $y) # BLAS built-in axpy
VERSION
```

With 8 Julia threads (pinned to different CPU-cores) I find the following results.

```julia
julia> @benchmark axpy_serial!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.430 μs …  2.226 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.434 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.438 μs ± 23.775 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▂█▃                                                         
  ███▆▆▄▂▁▂▂▁▁▂▁▁▁▁▁▂▁▂▁▁▁▁▁▁▂▂▁▁▂▁▂▁▁▁▁▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▂▂▂▂ ▂
  1.43 μs        Histogram: frequency by time        1.55 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark axpy_batch!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 69 evaluations.
 Range (min … max):  853.623 ns …  2.361 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     885.507 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   889.184 ns ± 25.306 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

              ▂▅▇██▆▆▄▁                                         
  ▁▁▁▁▁▁▂▂▃▄▆██████████▇▅▄▃▂▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▂▂▁▁ ▃
  854 ns          Histogram: frequency by time          968 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark axpy_atthreads!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 7 evaluations.
 Range (min … max):  4.437 μs … 388.400 μs  ┊ GC (min … max): 0.00% … 97.02%
 Time  (median):     5.077 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   5.560 μs ±   9.340 μs  ┊ GC (mean ± σ):  4.03% ±  2.37%

         ▁▄▅██▇▆▃▁                                             
  ▁▁▁▂▃▅▆█████████▆▅▄▄▃▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▂▂▂▂▂▃▂▃▃▃▂▂▂▂▂▂▁ ▃
  4.44 μs         Histogram: frequency by time        7.44 μs <

 Memory estimate: 4.54 KiB, allocs estimate: 48.

julia> @benchmark axpy_atthreads_static!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 8 evaluations.
 Range (min … max):  3.078 μs … 357.969 μs  ┊ GC (min … max): 0.00% … 96.65%
 Time  (median):     3.618 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   4.102 μs ±   9.118 μs  ┊ GC (mean ± σ):  5.75% ±  2.57%

         ▃▆█▆▅▂                                                
  ▂▂▂▃▄▆███████▇▅▄▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▂▁▂▂▂▂▂▂▂▂▃▂▃▃▃▃▃▃▃▃▃▃▃▃▂▂▂▂ ▃
  3.08 μs         Histogram: frequency by time        6.12 μs <

 Memory estimate: 4.56 KiB, allocs estimate: 48.

julia> @benchmark axpy!(eps(), $x, $y) # BLAS built-in axpy
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.438 μs …  9.397 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.441 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.445 μs ± 83.630 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

   █                                                          
  ▄██▅▆▂▂▁▁▂▁▁▂▁▁▁▁▁▂▂▁▁▁▂▁▁▂▁▁▁▁▁▁▁▂▂▁▁▁▁▂▂▁▂▂▁▁▁▁▁▁▁▁▂▂▂▂▂ ▂
  1.44 μs        Histogram: frequency by time        1.55 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> VERSION
v"1.9.3"
```

With only `10_000` elements, this simple AXPY computation can't afford the overhead of multithreading via `@threads` (for either scheduling scheme). In fact, the latter just slows the computation down. Similarly, the built-in BLAS `axpy!` doesn't provide any multithreading speedup (it likely falls back to a serial variant). Only with Polyester's `@batch`, which has minimal overhead, do we get a decent(!) speedup.

## Keyword options for `@batch`

### `per=cores` / `per=threads`

The `per` keyword argument can be used to limit the number of Julia threads to be used by a `@batch` block. Specifically, `per=core` will use only `max(num_cores, nthreads())` many of the Julia threads.

Note that `@batch` defaults to `per=cores`. This is because [LoopVectorization.jl](https://github.com/JuliaSIMD/LoopVectorization.jl) currently only uses up to 1 thread per physical core, and switching the number of
threads incurs some overhead.

### `minbatch`

The `minbatch` argument lets us choose a minimum number of iterations per thread. That is, `minbatch=n` means it'll use at most `number_loop_iterations ÷ n` threads.

For our benchmark example above with 10000 iterations, setting `minbatch=2500` will lead to `@batch` using only 4 (of 8) threads. This is still faster than the serial version but slower than plain `@batch`, which uses all 8 available threads.

```julia
function axpy_minbatch!(y, a, x)
    @batch minbatch=2500 for i in eachindex(y,x)
        @inbounds y[i] = a * x[i] + y[i]
    end
end

@benchmark axpy_minbatch!($y, $eps(), $x)
```

```julia
julia> @benchmark axpy_minbatch!($y, $eps(), $x)
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.072 μs …  5.085 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.114 μs              ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.126 μs ± 72.510 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

       ▂▅██▅▃                                                 
  ▁▁▂▃▆███████▅▃▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▂
  1.07 μs        Histogram: frequency by time        1.36 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

### Local per-thread storage (`threadlocal`)

You also can define local storage for each thread, providing a vector containing each of the local storages at the end.

```julia
julia> let
           @batch threadlocal=rand(10:99) for i in 0:9
               println("index $i, thread $(Threads.threadid()), local storage $threadlocal")
               threadlocal += 1
           end
           println(threadlocal)
       end

index 8, thread 1, local storage 30
index 3, thread 3, local storage 49
index 9, thread 1, local storage 31
index 6, thread 4, local storage 33
index 0, thread 2, local storage 14
index 4, thread 3, local storage 50
index 7, thread 4, local storage 34
index 1, thread 2, local storage 15
index 5, thread 3, local storage 51
index 2, thread 2, local storage 16
Any[32, 17, 52, 35]
```

Optionally, a type can be specified for the thread-local storage:
```julia
julia> let
           @batch threadlocal=rand(10:99)::Float16 for i in 0:9
           end
           println(threadlocal)
       end

Float16[83.0, 90.0, 27.0, 65.0]
```

### `reduction`
The `reduction` keyword enables reduction of an already initialized `isbits` variable with certain supported associative operations (see [docs](https://JuliaSIMD.github.io/Polyester.jl/stable)), such that the transition from serialized code is as simple as adding the `@batch` macro.

```julia
julia> let
           y1 = 0
           y2 = 1
           @batch reduction=((+, y1), (*, y2)) for i in 1:9
               y1 += i
               y2 *= i
           end
           println(y1, y2)
       end

45, 362880
```

## Disabling Polyester threads

When running many repetitions of a Polyester-multithreaded function (e.g. in an embarrassingly parallel problem that repeatedly executes a small already Polyester-multithreaded function), it can be beneficial to disable Polyester (the inner multithreaded loop) and multithread only at the outer level (e.g. with `Base.Threads`). This can be done with the `disable_polyester_threads` context manager. In the expandable section below you can see examples with benchmarks.

It is best to call `disable_polyester_threads` only once, before any `@thread` uses happen, to avoid overhead. E.g. best to do it as:
```julia
disable_polyester_threads() do
    @threads for i in 1:n
        f()
    end
end
```
instead of doing it in the following unnecessarily slow manner:
```julia
@threads for i in 1:n # DO NOT DO THIS
    disable_polyester_threads() do # IT HAS UNNECESSARY OVERHEAD
        f()
    end
end
```


<details>
<summary>Benchmarks of nested multi-threading with Polyester</summary>
    
```julia
# Big inner problem, repeated only a few times

y = rand(10000000,4);
x = rand(size(y)...);

@btime inner($x,$y,1) # 57.456 ms (0 allocations: 0 bytes)
@btime inner_polyester($x,$y,1) # 7.456 ms (0 allocations: 0 bytes)
@btime inner_thread($x,$y,1) # 7.286 ms (49 allocations: 4.56 KiB)

@btime sequential_sequential($x,$y) # 229.513 ms (0 allocations: 0 bytes)
@btime sequential_polyester($x,$y) # 29.921 ms (0 allocations: 0 bytes)
@btime sequential_thread($x,$y) # 29.343 ms (196 allocations: 18.25 KiB)

@btime threads_of_polyester($x,$y) # 29.961 ms (42 allocations: 4.34 KiB)
# the following is a purposefully suboptimal way to disable threads
@btime threads_of_polyester_inner_disable($x,$y) # 55.397 ms (51 allocations: 4.62 KiB)
# the following is a good way to disable threads (the disable call happening once in the outer scope)
@btime Polyester.disable_polyester_threads() do; threads_of_polyester($x,$y) end; # 55.396 ms (47 allocations: 4.50 KiB)
@btime threads_of_sequential($x,$y) # 55.404 ms (48 allocations: 4.53 KiB)
@btime threads_of_thread($x,$y) # 29.187 ms (220 allocations: 22.03 KiB)

# Small inner problem, repeated many times

y = rand(1000,1000);
x = rand(size(y)...);

@btime inner($x,$y,1) # 3.390 μs (0 allocations: 0 bytes)
@btime inner_polyester($x,$y,1) # 785.714 ns (0 allocations: 0 bytes)
@btime inner_thread($x,$y,1) # 4.043 μs (48 allocations: 4.54 KiB)

@btime sequential_sequential($x,$y) # 5.720 ms (0 allocations: 0 bytes)
@btime sequential_polyester($x,$y) # 1.143 ms (0 allocations: 0 bytes)
@btime sequential_thread($x,$y) # 4.796 ms (50307 allocations: 4.50 MiB)

@btime threads_of_polyester($x,$y) # 1.165 ms (42 allocations: 4.34 KiB)
# the following is a purposefully suboptimal way to disable threads
@btime threads_of_polyester_inner_disable($x,$y) # 779.713 μs (1042 allocations: 35.59 KiB)
# the following is a good way to disable threads (the disable call happening once in the outer scope)
@btime Polyester.disable_polyester_threads() do; threads_of_polyester($x,$y) end; # 743.813 μs (48 allocations: 4.53 KiB)
@btime threads_of_sequential($x,$y) # 694.463 μs (45 allocations: 4.44 KiB)
@btime threads_of_thread($x,$y) # 2.288 ms (42058 allocations: 4.25 MiB)

# The tested functions
# All of these would be better implemented by just using @tturbo,
# but these suboptimal implementations serve as good test case for
# Polyster-vs-Base thread scheduling.

function inner(x,y,j)
    for i ∈ axes(x,1)
        y[i,j] = sin(x[i,j])
    end
end

function inner_polyester(x,y,j)
    @batch for i ∈ axes(x,1)
        y[i,j] = sin(x[i,j])
    end
end

function inner_thread(x,y,j)
    @threads for i ∈ axes(x,1)
        y[i,j] = sin(x[i,j])
    end
end

function sequential_sequential(x,y)
    for j ∈ axes(x,2)
        inner(x,y,j)
    end
end

function sequential_polyester(x,y)
    for j ∈ axes(x,2)
        inner_polyester(x,y,j)
    end
end

function sequential_thread(x,y)
    for j ∈ axes(x,2)
        inner_thread(x,y,j)
    end
end

function threads_of_polyester(x,y)
    @threads for j ∈ axes(x,2)
        inner_polyester(x,y,j)
    end
end

function threads_of_polyester_inner_disable(x,y)
    # XXX This is a bad way to disable Polyester threads as
    # it causes unnecessary overhead for each @threads thread.
    # See the benchmarks above for a better way.
    @threads for j ∈ axes(x,2)
        Polyester.disable_polyester_threads() do
            inner_polyester(x,y,j)
        end
    end
end

function threads_of_thread(x,y)
    @threads for j ∈ axes(x,2)
        inner_thread(x,y,j)
    end
end

function threads_of_thread(x,y)
    @threads for j ∈ axes(x,2)
        inner_thread(x,y,j)
    end
end

function threads_of_sequential(x,y)
    @threads for j ∈ axes(x,2)
        inner(x,y,j)
    end
end
```
Benchmarks executed on:
```
Julia Version 1.9.3
Commit bed2cd540a1 (2023-08-24 14:43 UTC)
Build Info:
  Official https://julialang.org/ release
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: 128 × AMD EPYC 7V13 64-Core Processor
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-14.0.6 (ORCJIT, znver3)
  Threads: 8 on 128 virtual cores
Environment:
  JULIA_NUM_THREADS = 8
```
</details>
