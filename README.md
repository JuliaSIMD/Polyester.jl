# Polyester

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSIMD.github.io/Polyester.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSIMD.github.io/Polyester.jl/dev)
[![CI](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI.yml)
[![CI-Nightly](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI-julia-nightly.yml/badge.svg)](https://github.com/JuliaSIMD/Polyester.jl/actions/workflows/CI-julia-nightly.yml)
[![Coverage](https://codecov.io/gh/JuliaSIMD/Polyester.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaSIMD/Polyester.jl)


Polyester.jl provides low overhead threading.
The primary API is `@batch`, which can be used in place of `Threads.@threads`.
Lets look at a simple benchmark.
```julia
using Polyester, LinearAlgebra, BenchmarkHistograms
# Single threaded.
function axpy_serial!(y, a, x)
    @inbounds for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end
# One thread per core, the default
function axpy_per_core!(y, a, x)
    @batch per=core for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end
# One thread per thread
function axpy_per_thread!(y, a, x)
    @batch per=thread for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end
# Set a minimum batch size of `200`
function axpy_minbatch!(y, a, x)
    @batch minbatch=2000 for i in eachindex(y,x)
        y[i] = muladd(a, x[i], y[i])
    end
end
# benchmark against `Threads.@threads`
function axpy_atthread!(y, a, x)
    Threads.@threads for i in eachindex(y,x)
        @inbounds y[i] = muladd(a, x[i], y[i])
    end
end

y = rand(10_000);
x = rand(10_000);
@benchmark axpy_serial!($y, eps(), $x)
@benchmark axpy!(eps(), $x, $y)
@benchmark axpy_atthread!($y, eps(), $x)
@benchmark axpy_per_core!($y, eps(), $x)
@benchmark axpy_per_thread!($y, eps(), $x)
@benchmark axpy_minbatch!($y, eps(), $x)
versioninfo()
```
With only `10_000` elements, this simply `muladd` loop can't afford the overhead of threads like `BLAS` or `Threads.@threads`,
they just slow the computations down. But these 10_000 elements can afford `Polyester`, giving up to a >2x speedup on 4 cores.
```julia
julia> @benchmark axpy_serial!($y, eps(), $x)
samples: 10000; evals/sample: 10; memory estimate: 0 bytes; allocs estimate: 0
ns

 (1160.0 - 1240.0]  ██████████████████████████████ 9573
 (1240.0 - 1320.0]  █306
 (1320.0 - 1390.0]  ▎53
 (1390.0 - 1470.0]  ▏25
 (1470.0 - 1550.0]   0
 (1550.0 - 1620.0]   0
 (1620.0 - 1700.0]   0
 (1700.0 - 1780.0]   0
 (1780.0 - 1860.0]   0
 (1860.0 - 1930.0]   0
 (1930.0 - 2010.0]   0
 (2010.0 - 2090.0]   0
 (2090.0 - 2160.0]   0
 (2160.0 - 2240.0]  ▏32
 (2240.0 - 3230.0]  ▏11

                  Counts

min: 1.161 μs (0.00% GC); mean: 1.182 μs (0.00% GC); median: 1.169 μs (0.00% GC); max: 3.226 μs (0.00% GC).

julia> @benchmark axpy!(eps(), $x, $y)
samples: 10000; evals/sample: 9; memory estimate: 0 bytes; allocs estimate: 0
ns

 (2030.0 - 2160.0]  ██████████████████████████████ 9415
 (2160.0 - 2300.0]  █▋497
 (2300.0 - 2430.0]  ▎49
 (2430.0 - 2570.0]  ▏5
 (2570.0 - 2700.0]   0
 (2700.0 - 2840.0]  ▏1
 (2840.0 - 2970.0]   0
 (2970.0 - 3110.0]   0
 (3110.0 - 3240.0]  ▏1
 (3240.0 - 3370.0]   0
 (3370.0 - 3510.0]   0
 (3510.0 - 3640.0]  ▏1
 (3640.0 - 3780.0]   0
 (3780.0 - 3910.0]  ▏21
 (3910.0 - 4880.0]  ▏10

                  Counts

min: 2.030 μs (0.00% GC); mean: 2.060 μs (0.00% GC); median: 2.039 μs (0.00% GC); max: 4.881 μs (0.00% GC).

julia> @benchmark axpy_atthread!($y, eps(), $x)
samples: 10000; evals/sample: 7; memory estimate: 3.66 KiB; allocs estimate: 41
ns

 (3700.0  - 4600.0  ]  ██████████████████████████████▏7393
 (4600.0  - 5500.0  ]  ███▌852
 (5500.0  - 6400.0  ]  ██████▍1556
 (6400.0  - 7300.0  ]  ▊175
 (7300.0  - 8200.0  ]  ▏7
 (8200.0  - 9100.0  ]  ▏3
 (9100.0  - 10000.0 ]   0
 (10000.0 - 10900.0 ]   0
 (10900.0 - 11800.0 ]  ▏1
 (11800.0 - 12800.0 ]   0
 (12800.0 - 13700.0 ]  ▏1
 (13700.0 - 14600.0 ]   0
 (14600.0 - 15500.0 ]   0
 (15500.0 - 16400.0 ]  ▏1
 (16400.0 - 880700.0]  ▏11

                  Counts

min: 3.662 μs (0.00% GC); mean: 4.909 μs (6.36% GC); median: 4.226 μs (0.00% GC); max: 880.721 μs (93.63% GC).

julia> @benchmark axpy_per_core!($y, eps(), $x)
samples: 10000; evals/sample: 194; memory estimate: 0 bytes; allocs estimate: 0
ns

 (496.0 - 504.0 ]  ██████████████████████████████ 5969
 (504.0 - 513.0 ]  ██████████████████3564
 (513.0 - 522.0 ]  ██▏420
 (522.0 - 531.0 ]  ▏9
 (531.0 - 539.0 ]  ▏4
 (539.0 - 548.0 ]  ▏1
 (548.0 - 557.0 ]  ▏7
 (557.0 - 565.0 ]  ▏3
 (565.0 - 574.0 ]  ▏2
 (574.0 - 583.0 ]   0
 (583.0 - 591.0 ]  ▏1
 (591.0 - 600.0 ]  ▏4
 (600.0 - 609.0 ]  ▏3
 (609.0 - 617.0 ]  ▏2
 (617.0 - 1181.0]  ▏11

                  Counts

min: 495.758 ns (0.00% GC); mean: 505.037 ns (0.00% GC); median: 503.884 ns (0.00% GC); max: 1.181 μs (0.00% GC).

julia> @benchmark axpy_per_thread!($y, eps(), $x)
samples: 10000; evals/sample: 181; memory estimate: 0 bytes; allocs estimate: 0
ns

 (583.0 - 611.0 ]  ██████████████████████████████ 8489
 (611.0 - 640.0 ]  █████▎1453
 (640.0 - 669.0 ]  ▏21
 (669.0 - 697.0 ]  ▏12
 (697.0 - 726.0 ]  ▏5
 (726.0 - 755.0 ]  ▏2
 (755.0 - 783.0 ]  ▏2
 (783.0 - 812.0 ]  ▏1
 (812.0 - 841.0 ]   0
 (841.0 - 869.0 ]   0
 (869.0 - 898.0 ]  ▏1
 (898.0 - 927.0 ]   0
 (927.0 - 955.0 ]   0
 (955.0 - 984.0 ]  ▏3
 (984.0 - 9088.0]  ▏11

                  Counts

min: 582.608 ns (0.00% GC); mean: 609.063 ns (0.00% GC); median: 606.028 ns (0.00% GC); max: 9.088 μs (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 195; memory estimate: 0 bytes; allocs estimate: 0
ns

 (484.0 - 514.0 ]  ██████████████████████████████9874
 (514.0 - 544.0 ]  ▎43
 (544.0 - 574.0 ]  ▏24
 (574.0 - 604.0 ]  ▏18
 (604.0 - 634.0 ]  ▏13
 (634.0 - 664.0 ]  ▏2
 (664.0 - 694.0 ]  ▏1
 (694.0 - 724.0 ]  ▏1
 (724.0 - 754.0 ]   0
 (754.0 - 784.0 ]  ▏8
 (784.0 - 814.0 ]   0
 (814.0 - 844.0 ]   0
 (844.0 - 874.0 ]  ▏2
 (874.0 - 904.0 ]  ▏3
 (904.0 - 3364.0]  ▏11

                  Counts

min: 484.082 ns (0.00% GC); mean: 502.104 ns (0.00% GC); median: 499.708 ns (0.00% GC); max: 3.364 μs (0.00% GC).

julia> versioninfo()
Julia Version 1.7.0-DEV.1150
Commit a08a3ff1f9* (2021-05-22 21:10 UTC)
Platform Info:
  OS: Linux (x86_64-redhat-linux)
  CPU: 11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz
  WORD_SIZE: 64
  LIBM: libopenlibm
  LLVM: libLLVM-12.0.0 (ORCJIT, tigerlake)
Environment:
  JULIA_NUM_THREADS = 8
```

The `minbatch` argument lets us choose a minimum number of iterations per thread. That is, `minbatch=n` means it'll use at most
`number_loop_iterations ÷ n` threads. Setting `minbatch=2000` like we did above means that with only 4000 iterations, `@batch`
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

Float16[83.0, 90.0, 27.0, 65.0
```