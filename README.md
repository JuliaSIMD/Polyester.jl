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
# One thread per core, the default
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

 (1171.0 - 1192.0]  ██████████████████████████████6761
 (1192.0 - 1214.0]  ██████████▉2442
 (1214.0 - 1235.0]   0
 (1235.0 - 1256.0]  ▏18
 (1256.0 - 1277.0]  ▍60
 (1277.0 - 1298.0]  ▏25
 (1298.0 - 1319.0]  ▍63
 (1319.0 - 1341.0]  ██▍520
 (1341.0 - 1362.0]  ▏8
 (1362.0 - 1383.0]  ▏11
 (1383.0 - 1404.0]  ▏9
 (1404.0 - 1425.0]  ▏10
 (1425.0 - 1446.0]  ▏12
 (1446.0 - 1467.0]  ▎50
 (1467.0 - 2080.0]  ▏11

                  Counts

min: 1.171 μs (0.00% GC); mean: 1.197 μs (0.00% GC); median: 1.180 μs (0.00% GC); max: 2.080 μs (0.00% GC).

julia> @benchmark axpy!(eps(), $x, $y)
samples: 10000; evals/sample: 9; memory estimate: 0 bytes; allocs estimate: 0
ns

 (2077.0 - 2114.0]  ██████████████████████████████ 9162
 (2114.0 - 2151.0]   0
 (2151.0 - 2188.0]  ▌144
 (2188.0 - 2225.0]  ▏15
 (2225.0 - 2262.0]  ▏12
 (2262.0 - 2299.0]  ▏13
 (2299.0 - 2336.0]  ▎59
 (2336.0 - 2373.0]  █▊500
 (2373.0 - 2410.0]  ▏11
 (2410.0 - 2447.0]  ▏10
 (2447.0 - 2484.0]  ▏19
 (2484.0 - 2522.0]  ▏7
 (2522.0 - 2559.0]   0
 (2559.0 - 2596.0]  ▏37
 (2596.0 - 3672.0]  ▏11

                  Counts

min: 2.077 μs (0.00% GC); mean: 2.106 μs (0.00% GC); median: 2.086 μs (0.00% GC); max: 3.672 μs (0.00% GC).

julia> @benchmark axpy_atthread!($y, eps(), $x)
samples: 10000; evals/sample: 8; memory estimate: 3.66 KiB; allocs estimate: 41
ns

 (3700.0  - 5100.0  ]  ██████████████████████████████ 8433
 (5100.0  - 6500.0  ]  █████▏1435
 (6500.0  - 7900.0  ]  ▌106
 (7900.0  - 9300.0  ]  ▏6
 (9300.0  - 10700.0 ]  ▏2
 (10700.0 - 12100.0 ]  ▏1
 (12100.0 - 13500.0 ]  ▏1
 (13500.0 - 14900.0 ]  ▏1
 (14900.0 - 16200.0 ]  ▏1
 (16200.0 - 17600.0 ]  ▏1
 (17600.0 - 19000.0 ]  ▏1
 (19000.0 - 20400.0 ]   0
 (20400.0 - 21800.0 ]   0
 (21800.0 - 23200.0 ]  ▏1
 (23200.0 - 589100.0]  ▏11

                  Counts

min: 3.711 μs (0.00% GC); mean: 4.726 μs (4.85% GC); median: 4.224 μs (0.00% GC); max: 589.062 μs (82.15% GC).

julia> @benchmark axpy_per_core!($y, eps(), $x)
samples: 10000; evals/sample: 187; memory estimate: 0 bytes; allocs estimate: 0
ns

 (536.0 - 546.0 ]  ▌75
 (546.0 - 555.0 ]  ▊115
 (555.0 - 564.0 ]  ▎21
 (564.0 - 573.0 ]  ▏13
 (573.0 - 583.0 ]  █▍228
 (583.0 - 592.0 ]  ████████████████████3327
 (592.0 - 601.0 ]  ██████████████████████████████ 5000
 (601.0 - 611.0 ]  ██████▋1100
 (611.0 - 620.0 ]  ▋90
 (620.0 - 629.0 ]  ▏8
 (629.0 - 638.0 ]  ▏2
 (638.0 - 648.0 ]  ▏1
 (648.0 - 657.0 ]  ▏5
 (657.0 - 666.0 ]  ▏4
 (666.0 - 1184.0]  ▏11

                  Counts

min: 536.267 ns (0.00% GC); mean: 593.644 ns (0.00% GC); median: 593.963 ns (0.00% GC); max: 1.184 μs (0.00% GC).

julia> @benchmark axpy_per_thread!($y, eps(), $x)
samples: 10000; evals/sample: 49; memory estimate: 0 bytes; allocs estimate: 0
ns

 (827.0  - 842.0 ]  ▍43
 (842.0  - 857.0 ]  ████▎558
 (857.0  - 872.0 ]  ███████████████████▌2579
 (872.0  - 887.0 ]  ██████████████████████████████ 3979
 (887.0  - 902.0 ]  ████████████████▎2151
 (902.0  - 917.0 ]  ███▉505
 (917.0  - 932.0 ]  █130
 (932.0  - 947.0 ]  ▎21
 (947.0  - 962.0 ]  ▏1
 (962.0  - 977.0 ]  ▏1
 (977.0  - 992.0 ]  ▏5
 (992.0  - 1007.0]  ▏9
 (1007.0 - 1022.0]  ▏4
 (1022.0 - 1037.0]  ▏3
 (1037.0 - 2751.0]  ▏11

                  Counts

min: 827.347 ns (0.00% GC); mean: 880.205 ns (0.00% GC); median: 878.878 ns (0.00% GC); max: 2.751 μs (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 192; memory estimate: 0 bytes; allocs estimate: 0
ns

 (508.0 - 521.0 ]  ▌83
 (521.0 - 534.0 ]  ▌81
 (534.0 - 548.0 ]  ▏12
 (548.0 - 561.0 ]  ███▏530
 (561.0 - 574.0 ]  ██████████████████████████████ 5144
 (574.0 - 587.0 ]  ███████████████████▎3280
 (587.0 - 600.0 ]  ███▌583
 (600.0 - 613.0 ]  █▎199
 (613.0 - 626.0 ]  ▍51
 (626.0 - 640.0 ]  ▏18
 (640.0 - 653.0 ]  ▏2
 (653.0 - 666.0 ]  ▏1
 (666.0 - 679.0 ]  ▏1
 (679.0 - 692.0 ]  ▏4
 (692.0 - 1125.0]  ▏11

                  Counts

min: 508.219 ns (0.00% GC); mean: 573.149 ns (0.00% GC); median: 571.901 ns (0.00% GC); max: 1.125 μs (0.00% GC).

julia> versioninfo() # 4 cores, 8 threads
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
than the serial version, while using 4 threads (`per=core`) it is only slightly faster, and the full 8 (`per=thread`) makes it slower.
```julia
julia> x = rand(4_000); y = rand(4_000);

julia> @benchmark axpy_serial!($y, eps(), $x)
samples: 10000; evals/sample: 195; memory estimate: 0 bytes; allocs estimate: 0
ns

 (477.0 - 486.0]  ████████▊2050
 (486.0 - 494.0]  ██████████████████████████████▏7033
 (494.0 - 502.0]  █▌336
 (502.0 - 510.0]  ▎35
 (510.0 - 519.0]  ▎44
 (519.0 - 527.0]  ▎47
 (527.0 - 535.0]  ▎37
 (535.0 - 543.0]  █▊383
 (543.0 - 552.0]  ▏15
 (552.0 - 560.0]  ▏4
 (560.0 - 568.0]  ▏1
 (568.0 - 576.0]   0
 (576.0 - 585.0]  ▏3
 (585.0 - 593.0]  ▏1
 (593.0 - 846.0]  ▏11

                  Counts

min: 477.390 ns (0.00% GC); mean: 490.102 ns (0.00% GC); median: 489.005 ns (0.00% GC); max: 846.451 ns (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 328; memory estimate: 0 bytes; allocs estimate: 0
ns

 (261.6 - 265.7]  █120
 (265.7 - 269.8]  █████████▉1246
 (269.8 - 273.9]  ███████▊981
 (273.9 - 278.0]  █▍167
 (278.0 - 282.1]  ▊89
 (282.1 - 286.1]  █▎146
 (286.1 - 290.2]  ██████████████▌1840
 (290.2 - 294.3]  ██████████████████████████████ 3825
 (294.3 - 298.4]  █████████▍1191
 (298.4 - 302.5]  ██241
 (302.5 - 306.6]  ▉97
 (306.6 - 310.7]  ▍32
 (310.7 - 314.7]  ▏7
 (314.7 - 318.8]  ▏7
 (318.8 - 632.0]  ▏11

                  Counts

min: 261.616 ns (0.00% GC); mean: 286.596 ns (0.00% GC); median: 290.665 ns (0.00% GC); max: 631.951 ns (0.00% GC).

julia> @benchmark axpy_per_core!($y, eps(), $x)
samples: 10000; evals/sample: 200; memory estimate: 0 bytes; allocs estimate: 0
ns

 (399.7 - 406.2]  ▍46
 (406.2 - 412.8]  ▉127
 (412.8 - 419.3]  ▍56
 (419.3 - 425.9]  █148
 (425.9 - 432.4]  ███████████▍1684
 (432.4 - 439.0]  ██████████████████████████████ 4483
 (439.0 - 445.5]  █████████████████▉2653
 (445.5 - 452.1]  ████▏615
 (452.1 - 458.6]  █140
 (458.6 - 465.2]  ▎20
 (465.2 - 471.7]   0
 (471.7 - 478.3]  ▏11
 (478.3 - 484.8]  ▏3
 (484.8 - 491.3]  ▏3
 (491.3 - 969.9]  ▏11

                  Counts

min: 399.680 ns (0.00% GC); mean: 436.958 ns (0.00% GC); median: 436.790 ns (0.00% GC); max: 969.865 ns (0.00% GC).

julia> @benchmark axpy_per_thread!($y, eps(), $x)
samples: 10000; evals/sample: 126; memory estimate: 0 bytes; allocs estimate: 0
ns

 (727.0 - 735.0 ]  ▏10
 (735.0 - 742.0 ]  █▌147
 (742.0 - 750.0 ]  ███████▎748
 (750.0 - 757.0 ]  ████████████████████▏2079
 (757.0 - 765.0 ]  ██████████████████████████████ 3111
 (765.0 - 772.0 ]  ██████████████████████▉2368
 (772.0 - 780.0 ]  ██████████▊1102
 (780.0 - 787.0 ]  ███304
 (787.0 - 794.0 ]  ▉86
 (794.0 - 802.0 ]  ▎24
 (802.0 - 809.0 ]  ▏5
 (809.0 - 817.0 ]  ▏1
 (817.0 - 824.0 ]  ▏1
 (824.0 - 832.0 ]  ▏3
 (832.0 - 4038.0]  ▏11

                  Counts

min: 727.468 ns (0.00% GC); mean: 762.998 ns (0.00% GC); median: 762.103 ns (0.00% GC); max: 4.038 μs (0.00% GC).
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
samples: 10000; evals/sample: 886; memory estimate: 0 bytes; allocs estimate: 0
ns

 (129.2 - 131.3]  ██████████████████████████████3587
 (131.3 - 133.5]  ███████████████████████████▏3229
 (133.5 - 135.6]  ████████████████████▉2493
 (135.6 - 137.8]  ▋69
 (137.8 - 139.9]  ▌49
 (139.9 - 142.0]  ▌55
 (142.0 - 144.2]  █▍153
 (144.2 - 146.3]  █▋182
 (146.3 - 148.5]  █▍152
 (148.5 - 150.6]  ▎19
 (150.6 - 152.7]   0
 (152.7 - 154.9]   0
 (154.9 - 157.0]   0
 (157.0 - 159.2]  ▏1
 (159.2 - 217.7]  ▏11

                  Counts

min: 129.193 ns (0.00% GC); mean: 132.555 ns (0.00% GC); median: 131.503 ns (0.00% GC); max: 217.734 ns (0.00% GC).

julia> @benchmark axpy_minbatch!($y, eps(), $x)
samples: 10000; evals/sample: 870; memory estimate: 0 bytes; allocs estimate: 0
ns

 (134.1 - 135.8]  ██████▉611
 (135.8 - 137.4]  ██████████▎913
 (137.4 - 139.1]  ████████████████████████████▎2525
 (139.1 - 140.7]  ██████████████████████████████ 2683
 (140.7 - 142.4]  ████████████████1427
 (142.4 - 144.0]  █████████████▍1192
 (144.0 - 145.7]  █79
 (145.7 - 147.4]  ▊62
 (147.4 - 149.0]  ██▌214
 (149.0 - 150.7]  ██▋229
 (150.7 - 152.3]  ▌42
 (152.3 - 154.0]  ▏5
 (154.0 - 155.6]  ▏1
 (155.6 - 157.3]  ▏6
 (157.3 - 226.5]  ▏11

                  Counts

min: 134.100 ns (0.00% GC); mean: 139.874 ns (0.00% GC); median: 139.334 ns (0.00% GC); max: 226.483 ns (0.00% GC).

julia> @benchmark axpy_minbatch_1500!($y, eps(), $x)
samples: 10000; evals/sample: 230; memory estimate: 0 bytes; allocs estimate: 0
ns

 (263.0 - 274.0]   0
 (274.0 - 285.0]   0
 (285.0 - 295.0]   0
 (295.0 - 306.0]  ▏1
 (306.0 - 316.0]  ▏1
 (316.0 - 327.0]  ▏1
 (327.0 - 337.0]  ▎65
 (337.0 - 348.0]  ██████████████████████████████▏8708
 (348.0 - 358.0]  ███869
 (358.0 - 369.0]  ▉238
 (369.0 - 379.0]  ▎41
 (379.0 - 390.0]  ▏2
 (390.0 - 400.0]  ▏7
 (400.0 - 411.0]  ▎56
 (411.0 - 489.0]  ▏11

                  Counts

min: 263.465 ns (0.00% GC); mean: 344.388 ns (0.00% GC); median: 342.974 ns (0.00% GC); max: 489.209 ns (0.00% GC).
```
By reducing the length of the vectors by just 1/3 (4000 -> 3000), we saw over a 3.5x speedup in the serial version.
`minbatch=2000`, by also using only a single thread was able to match its performance. Thus, something around
`minbatch=2000` seems like the best choice for this particular function on this particular CPU.


Note that `@batch` defaults to using up to one thread per physical core, instead of 1 thread per CPU thread. This
is because [LoopVectorization.jl](https://github.com/JuliaSIMD/LoopVectorization.jl) currently only uses up to 1 thread per physical core, and switching the number of
threads incurs some overhead. See the docstring on `@batch` (i.e., `?@batch` in a Julia REPL) for some more discussion.

