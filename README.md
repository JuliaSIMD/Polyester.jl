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
x = rand(1024)
y = rand(1024)
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

On a 6-core machine I find the following results.

```julia
julia> @benchmark axpy_serial!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 9 evaluations.
 Range (min … max):  2.743 μs …  10.681 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     2.845 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   2.872 μs ± 205.675 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

         ▃▅██▇▆▄▃▁                                             
  ▁▁▂▂▄▆██████████▇▆▅▄▄▃▃▃▃▂▂▂▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  2.74 μs         Histogram: frequency by time        3.24 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark axpy_batch!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.859 μs …  12.354 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.946 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   2.143 μs ± 626.026 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▅█▅▃▂▁▁               ▁▂▃▁                                  ▁
  ██████████▇▇█▆▅▅▃▄▂▃▃▅████▆▆▅▅▅▅▄▃▄▄▅▅▄▅▅▅▄▅▃▅▅▅▆▅▄▃▃▃▄▄▄▃▄ █
  1.86 μs      Histogram: log(frequency) by time      4.88 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark axpy_atthreads!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):   5.714 μs … 172.895 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     16.372 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   18.357 μs ±   8.686 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

           ▅▇█▇▄▄▄▄▃▂▂▂▁▁                                      ▂
  ▄▅▅▆▄▁▅▄▆███████████████▇▇▇▇▆▆▇▆▅▆▆▅▆▆▇▅▆▆▇▆▆▇▆▅▅▆▅▆▆▅▄▄▄▄▅▄ █
  5.71 μs       Histogram: log(frequency) by time      59.9 μs <

 Memory estimate: 2.91 KiB, allocs estimate: 32.

julia> @benchmark axpy_atthreads_static!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 1 evaluation.
 Range (min … max):  12.196 μs … 212.525 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     29.006 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   33.643 μs ±  12.385 μs  ┊ GC (mean ± σ):  0.00% ± 0.00%

            ▆▆█▅▂▂▁ ▁▂▂▆▆▂▁                                    ▂
  ▄▄▆▆▆▆▆▇█████████████████████▇█▆▇▇▆▆▇▆▆▆▅▅▅▅▄▄▅▃▅▅▄▅▄▅▄▅▄▄▅▅ █
  12.2 μs       Histogram: log(frequency) by time      91.2 μs <

 Memory estimate: 3.03 KiB, allocs estimate: 36.

julia> @benchmark axpy!(eps(), $x, $y)
BenchmarkTools.Trial: 10000 samples with 9 evaluations.
 Range (min … max):  2.759 μs …   9.360 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     2.872 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   2.897 μs ± 170.550 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

          ▁▅▇█▇▇▆▆▄▃                                           
  ▁▁▁▂▃▄▅████████████▇▆▄▃▃▃▃▂▂▂▂▂▂▂▂▂▂▂▂▂▁▂▂▁▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▃
  2.76 μs         Histogram: frequency by time        3.23 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> VERSION
v"1.9.3"
```

With only `10_000` elements, this simple AXPY computation can't afford the overhead of multithreading via `@threads` (for either scheduling scheme). In fact, the latter just slows the computation down. Similarly, the built-in BLAS `axpy!` doesn't provide any multithreading speedup (it likely falls back to a serial variant). Only with Polyester's `@batch`, which has minimal overhead, do we decent(!) speedup.

## Keyword options for `@batch`

### `per=cores` / `per=threads`

```julia
# One Polyester task "per CPU-core" (default)
function axpy_per_core!(y, a, x)
    @batch per=core for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end

# One Polyester task "per CPU-thread"
function axpy_per_thread!(y, a, x)
    @batch per=thread for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end

y = rand(10_000);
x = rand(10_000);
@benchmark axpy_per_core!($y, eps(), $x)
@benchmark axpy_per_thread!($y, eps(), $x)
VERSION
```

Exemplatory results with 6 Julia threads:

```julia
julia> @benchmark axpy_per_core!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.572 μs …  22.768 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.829 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   2.053 μs ± 669.372 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

   █                                                           
  ▃██▇▂▁▁▁▂▆▄▃▃▃▂▂▁▂▃▆▃▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁ ▂
  1.57 μs         Histogram: frequency by time        4.54 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.

julia> @benchmark axpy_per_thread!($y, eps(), $x)
BenchmarkTools.Trial: 10000 samples with 10 evaluations.
 Range (min … max):  1.574 μs …  14.175 μs  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     1.678 μs               ┊ GC (median):    0.00%
 Time  (mean ± σ):   1.856 μs ± 526.368 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

  ▄██▆▃     ▁▂▃▄▁      ▁▃▃▂▁                                  ▂
  █████████▇█████▇▆▆▅▄▇█████▅▇▆▆▆▅▄▃▃▄▄▄▄▃▅▄▄▄▄▅▅▄▅▅▆▄▅▅▅▄▄▄▄ █
  1.57 μs      Histogram: log(frequency) by time      4.09 μs <

 Memory estimate: 0 bytes, allocs estimate: 0.
```

### `minibatch`

The `minbatch` argument lets us choose a minimum number of iterations per thread. That is, `minbatch=n` means it'll use at most `number_loop_iterations ÷ n` threads. Setting `minbatch=2000` like we did above means that with only 4000 iterations, `@batch`
will use just 2 threads; with 3999 iterations, it'll only only 1.
This lets us control the pace with which it ramps up threads. By using only 2 threads with 4000 iterations, it is still much faster
than the serial version, while using 4 threads (`per=core`) it is only slightly faster, and the full 8 (`per=thread`) matches serial.
```julia
julia> x = rand(4_000); y = rand(4_000);

julia> @benchmark axpy_serial!($y, eps(), $x)
samples: 10000; evals/sample: 196; memory estimate: 0 bytes; allocs estimate: 0
ns

 (477.0 - 484.0]  ██████1379
 (484.0 - 491.0]  ██████████████████████████████ 6931
 (491.0 - 499.0]  ████▍1004
 (499.0 - 506.0]  ▍71
 (506.0 - 513.0]  ▏28
 (513.0 - 520.0]  ▎47
 (520.0 - 528.0]  ▎45
 (528.0 - 535.0]  ▏20
 (535.0 - 542.0]  ██443
 (542.0 - 549.0]  ▏15
 (549.0 - 557.0]  ▏3
 (557.0 - 564.0]   0
 (564.0 - 571.0]   0
 (571.0 - 578.0]  ▏3
 (578.0 - 858.0]  ▏11

                  Counts

min: 476.867 ns (0.00% GC); mean: 490.402 ns (0.00% GC); median: 488.444 ns (0.00% GC); max: 858.056 ns (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 276; memory estimate: 0 bytes; allocs estimate: 0
ns

 (287.0 - 297.0]  ██████████████████▌2510
 (297.0 - 306.0]  ██████████████████████████████ 4088
 (306.0 - 316.0]  ███████████████████████▋3205
 (316.0 - 325.0]  █▎158
 (325.0 - 335.0]  ▎24
 (335.0 - 344.0]   0
 (344.0 - 354.0]  ▏1
 (354.0 - 364.0]   0
 (364.0 - 373.0]   0
 (373.0 - 383.0]   0
 (383.0 - 392.0]   0
 (392.0 - 402.0]   0
 (402.0 - 411.0]  ▏1
 (411.0 - 421.0]  ▏2
 (421.0 - 689.0]  ▏11

                  Counts

min: 286.938 ns (0.00% GC); mean: 302.339 ns (0.00% GC); median: 299.721 ns (0.00% GC); max: 689.467 ns (0.00% GC).

julia> @benchmark axpy_per_core!($y, eps(), $x)
samples: 10000; evals/sample: 213; memory estimate: 0 bytes; allocs estimate: 0
ns

 (344.0 - 351.0]  █▋325
 (351.0 - 359.0]  ██████████████████████████████ 6026
 (359.0 - 366.0]  ████████████████▏3229
 (366.0 - 373.0]  █▋321
 (373.0 - 381.0]  ▍55
 (381.0 - 388.0]  ▏12
 (388.0 - 396.0]  ▏7
 (396.0 - 403.0]  ▏6
 (403.0 - 410.0]  ▏1
 (410.0 - 418.0]   0
 (418.0 - 425.0]   0
 (425.0 - 433.0]  ▏1
 (433.0 - 440.0]  ▏5
 (440.0 - 447.0]  ▏1
 (447.0 - 795.0]  ▏11

                  Counts

min: 343.770 ns (0.00% GC); mean: 357.972 ns (0.00% GC); median: 357.270 ns (0.00% GC); max: 794.709 ns (0.00% GC).

julia> @benchmark axpy_per_thread!($y, eps(), $x)
samples: 10000; evals/sample: 195; memory estimate: 0 bytes; allocs estimate: 0
ns

 (476.0 - 487.0 ]  ██████████████████████████████▏7273
 (487.0 - 499.0 ]  ██████████▉2625
 (499.0 - 510.0 ]  ▎48
 (510.0 - 522.0 ]  ▏15
 (522.0 - 533.0 ]  ▏6
 (533.0 - 545.0 ]  ▏2
 (545.0 - 557.0 ]  ▏5
 (557.0 - 568.0 ]  ▏5
 (568.0 - 580.0 ]  ▏3
 (580.0 - 591.0 ]  ▏2
 (591.0 - 603.0 ]   0
 (603.0 - 614.0 ]   0
 (614.0 - 626.0 ]  ▏3
 (626.0 - 638.0 ]  ▏2
 (638.0 - 2489.0]  ▏11

                  Counts

min: 475.564 ns (0.00% GC); mean: 486.650 ns (0.00% GC); median: 485.287 ns (0.00% GC); max: 2.489 μs (0.00% GC).
```
Seeing that we still see a substantial improvement with 2 threads for vectors of length 4000, we may thus expect to still see
improvement for vectors of length 3000, and could thus try `minbatch=1_500`. That'd also ensure we're still using just 2 threads
for vectos of length 4000.
However, performance with respect to size tends to have a lot discontinuities.
```julia
julia> function axpy_minbatch_1500!(y, a, x)
           @batch minbatch=1_500 for i in eachindex(y,x)
               y[i] = muladd(a, x[i], y[i])
           end
       end
axpy_minbatch_1500! (generic function with 1 method)

julia> x = rand(3_000); y = rand(3_000);

julia> @benchmark axpy_serial!($y, eps(), $x)
samples: 10000; evals/sample: 839; memory estimate: 0 bytes; allocs estimate: 0
ns

 (145.3 - 151.6]  ██████████████████████████████9289
 (151.6 - 157.9]  ▌133
 (157.9 - 164.3]  █▋484
 (164.3 - 170.6]  ▏14
 (170.6 - 176.9]   0
 (176.9 - 183.3]  ▏2
 (183.3 - 189.6]  ▏9
 (189.6 - 195.9]  ▏6
 (195.9 - 202.2]  ▏6
 (202.2 - 208.6]  ▏5
 (208.6 - 214.9]  ▏4
 (214.9 - 221.2]  ▏9
 (221.2 - 227.6]  ▏14
 (227.6 - 233.9]  ▏14
 (233.9 - 260.2]  ▏11

                  Counts

min: 145.273 ns (0.00% GC); mean: 148.314 ns (0.00% GC); median: 145.881 ns (0.00% GC); max: 260.150 ns (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 807; memory estimate: 0 bytes; allocs estimate: 0
ns

 (148.6 - 153.6]  ██████████████████████████████ 8937
 (153.6 - 158.7]  ██▍674
 (158.7 - 163.8]  █292
 (163.8 - 168.9]  ▎71
 (168.9 - 174.0]  ▏4
 (174.0 - 179.0]  ▏3
 (179.0 - 184.1]   0
 (184.1 - 189.2]   0
 (189.2 - 194.3]   0
 (194.3 - 199.3]   0
 (199.3 - 204.4]   0
 (204.4 - 209.5]  ▏1
 (209.5 - 214.6]   0
 (214.6 - 219.6]  ▏7
 (219.6 - 742.4]  ▏11

                  Counts

min: 148.572 ns (0.00% GC); mean: 152.167 ns (0.00% GC); median: 152.376 ns (0.00% GC); max: 742.447 ns (0.00% GC).

julia> @benchmark axpy_minbatch_1500!($y, eps(), $x)
samples: 10000; evals/sample: 233; memory estimate: 0 bytes; allocs estimate: 0
ns

 (317.7 - 323.9]  ▍43
 (323.9 - 330.2]  ████▉591
 (330.2 - 336.4]  ████████████████████▉2538
 (336.4 - 342.6]  ██████████████████████████████3669
 (342.6 - 348.8]  ██████████████████▉2299
 (348.8 - 355.0]  █████▌667
 (355.0 - 361.2]  █▏129
 (361.2 - 367.4]  ▎21
 (367.4 - 373.6]  ▏13
 (373.6 - 379.8]  ▏5
 (379.8 - 386.0]  ▏2
 (386.0 - 392.2]  ▏2
 (392.2 - 398.4]  ▏5
 (398.4 - 404.6]  ▏5
 (404.6 - 791.4]  ▏11

                  Counts

min: 317.738 ns (0.00% GC); mean: 339.868 ns (0.00% GC); median: 339.279 ns (0.00% GC); max: 791.361 ns (0.00% GC).
```
By reducing the length of the vectors by just 1/3 (4000 -> 3000), we saw over a 3.5x speedup in the serial version.
`minbatch=2000`, by also using only a single thread was able to match its performance. Thus, something around
`minbatch=2000` seems like the best choice for this particular function on this particular CPU.


Note that `@batch` defaults to using up to one thread per physical core, instead of 1 thread per CPU thread. This
is because [LoopVectorization.jl](https://github.com/JuliaSIMD/LoopVectorization.jl) currently only uses up to 1 thread per physical core, and switching the number of
threads incurs some overhead. See the docstring on `@batch` (i.e., `?@batch` in a Julia REPL) for some more discussion.

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

@btime inner($x,$y,1) # 73.319 ms (0 allocations: 0 bytes)
@btime inner_polyester($x,$y,1) # 8.936 ms (0 allocations: 0 bytes)
@btime inner_thread($x,$y,1) # 11.206 ms (49 allocations: 4.56 KiB)

@btime sequential_sequential($x,$y) # 274.926 ms (0 allocations: 0 bytes)
@btime sequential_polyester($x,$y) # 36.963 ms (0 allocations: 0 bytes)
@btime sequential_thread($x,$y) # 49.373 ms (196 allocations: 18.25 KiB)

@btime threads_of_polyester($x,$y) # 78.828 ms (58 allocations: 4.84 KiB)
# the following is a purposefully suboptimal way to disable threads
@btime threads_of_polyester_inner_disable($x,$y) # 70.182 ms (47 allocations: 4.50 KiB)
# the following is a good way to disable threads (the disable call happening once in the outer scope)
@btime Polyester.disable_polyester_threads() do; threads_of_polyester($x,$y) end; # 71.141 ms (47 allocations: 4.50 KiB)
@btime threads_of_sequential($x,$y) # 70.857 ms (46 allocations: 4.47 KiB)
@btime threads_of_thread($x,$y) # 45.116 ms (219 allocations: 22.00 KiB)

# Small inner problem, repeated many times

y = rand(1000,1000);
x = rand(size(y)...);

@btime inner($x,$y,1) # 7.028 μs (0 allocations: 0 bytes)
@btime inner_polyester($x,$y,1) # 1.917 μs (0 allocations: 0 bytes)
@btime inner_thread($x,$y,1) # 7.544 μs (45 allocations: 4.44 KiB)

@btime sequential_sequential($x,$y) # 6.790 ms (0 allocations: 0 bytes)
@btime sequential_polyester($x,$y) # 2.070 ms (0 allocations: 0 bytes)
@btime sequential_thread($x,$y) # 9.296 ms (49002 allocations: 4.46 MiB)

@btime threads_of_polyester($x,$y) # 2.090 ms (42 allocations: 4.34 KiB)
# the following is a purposefully suboptimal way to disable threads
@btime threads_of_polyester_inner_disable($x,$y) # 1.065 ms (42 allocations: 4.34 KiB)
# the following is a good way to disable threads (the disable call happening once in the outer scope)
@btime Polyester.disable_polyester_threads() do; threads_of_polyester($x,$y) end; # 997.918 μs (49 allocations: 4.56 KiB)
@btime threads_of_sequential($x,$y) # 1.057 ms (48 allocations: 4.53 KiB)
@btime threads_of_thread($x,$y) # 4.105 ms (42059 allocations: 4.25 MiB)

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
Julia Version 1.9.0-DEV.998
Commit e1739aa42a1 (2022-07-18 10:27 UTC)
Platform Info:
  OS: Linux (x86_64-linux-gnu)
  CPU: 16 × AMD Ryzen 7 1700 Eight-Core Processor
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-14.0.5 (ORCJIT, znver1)
  Threads: 8 on 16 virtual cores
Environment:
  JULIA_EDITOR = code
  JULIA_NUM_THREADS = 8
```
</details>
