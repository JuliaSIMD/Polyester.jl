println("Starting tests with $(Threads.nthreads()) threads out of `Sys.CPU_THREADS = $(Sys.CPU_THREADS)`...")
using Polyester, Aqua, ForwardDiff
using Test

function bsin!(y,x)
  @batch for i ∈ eachindex(y,x)
    y[i] = sin(x[i])
  end
  return y
end
function bcos!(y,x)
  @batch per=core for i ∈ eachindex(y,x)
    local cxᵢ
    cxᵢ = cos(x[i])
    y[i] = cxᵢ
  end
  return y
end
myindices(x) = 1:length(x) # test hygiene, issue #11
function sin_batch_sum(v)
  s = zeros(8,Threads.nthreads())
  @batch minbatch=10 for i = myindices(v)
    s[1,Threads.threadid()] += sin(v[i])
  end
  if cld(length(v), 10) < Threads.nthreads()
    @test s[1,end] == 0.0
  end
  return sum(view(s, 1, :))
end
function rowsum_batch!(x, A)
  @batch for n ∈ axes(A,2)
    local s = 0.0
    @simd for m ∈ axes(A,1)
      s += A[m,n]
    end
    x[n] = s
  end
end
function bar!(dest, src)
    @batch for i in eachindex(dest)
        dest[i] = src.a.b[i]
    end
    dest
end

function rangemap!(f::F, allargs, start, stop) where {F}
    dest = first(allargs)
    args = Base.tail(allargs)
    @inbounds @simd for i ∈ start:stop
        dest[i] = f(Base.unsafe_getindex.(args, i)...)
    end
    nothing
end

function tmap!(f::F, args::Vararg{AbstractArray,K}) where {K,F}
    dest = first(args)
    N = length(dest)
    mapfun! = (allargs, start, stop) -> rangemap!(f, allargs, start, stop)
    batch(mapfun!, (N, num_threads()), args...)
    dest
end
function issue15!(dest, src)
    @batch for i in eachindex(src)
        dest.src[i] = src[i]
    end
    dest
end
function issue16!(dest)
    @batch for i in 2:1
        dest[i] = i
    end
    true
end
function issue17!(dest)
    @assert size(dest, 1) == 5
    @batch for j in axes(dest, 2)
        x = ntuple(i -> i*j, Val(5)) # works if this line is commented out
        for i in axes(dest, 1)
            dest[i, j] = i * j
        end
    end
end
function issue18!(dest)
    @assert length(dest) == 3
    @assert dest[1] == 1
    @batch for i in 2:3
        dest[i] = i
    end
    @test dest ≈ 1:3
end

function issue25!(dest, x, y)
    @batch for (i,j) ∈ Iterators.product(eachindex(x), eachindex(y))
        dest[i,j] = x[i,begin] * y[j,end]
    end
    dest
end

@testset "Range Map" begin

    x = rand(1024); y = rand(length(x)); z = similar(x);
    foo(x,y) = exp(-0.5abs2(x-y))
    println("Running `tmap!` test...")
    @test tmap!(foo, z, x, y) ≈ foo.(x, y)

    function slow_task!((x, digits, n), j, k)
        start = 1 + (n * (j - 1)) ÷ num_threads()
        stop =  (n* k) ÷ num_threads()
        target = 0.0
        for i ∈ start:stop
            target += occursin(digits, string(i)) ? 0.0 : 1.0 / i
        end
        x[1,j] = target
    end

    function slow_cheap(n, digits)
        x = zeros(8, num_threads())
        batch(slow_task!, (num_threads(), num_threads()), x, digits, n)
        sum(@view(x[1,1:end]))
    end

    function slow_single_thread(n, digits)
        target = 0.0
        for i ∈ 1:n
            target += occursin(digits, string(i)) ? 0.0 : 1.0 / i
        end
        return target
    end

    @test slow_cheap(1000, "9") ≈ slow_single_thread(1000,"9")

    x = randn(100_000); y = similar(x);
    @test bsin!(y, x) == sin.(x)
    @test bcos!(y, x) == cos.(x)
    @test sum(sin,x) ≈ sin_batch_sum(x)
    @test sum(sin,1:9) ≈ sin_batch_sum(1:9)
  
    A = rand(200,300); x = Vector{Float64}(undef, 300);
    rowsum_batch!(x, A);
    @test x ≈ vec(sum(A,dims=1))

    let dest = zeros(10^3), src = (; a = (; b = rand(length(dest))));
        @test bar!(dest, src) == src.a.b
    end
    let src = rand(100), dest = (; src = similar(src));
        @test issue15!(dest, src).src == src
        @test issue16!(dest)
    end
    let dest = zeros(5, 10_000);
        issue17!(dest)
        @test dest == axes(dest,1) .* axes(dest,2)'
    end
    issue18!(ones(3))

    let x = rand(100), y = rand(100), dest1 = x .* y'; dest0 = similar(dest1);
        # TODO: don't only thread outer
        @test issue25!(dest0, x, y) ≈ dest1
    end
end

@testset "start and stop values" begin
    println("Running start and stop values tests...")
    function record_start_stop!((start_indices, end_indices), start, stop)
      start_indices[Threads.threadid()] = start
      end_indices[Threads.threadid()] = stop
      sleep(1) # if task completes two quickly, the mainthread will start stealing work back.
    end

    start_indices = zeros(Int, num_threads());
    end_indices = zeros(Int, num_threads());

    for range in [Int(num_threads()), 1000, 1001]
        start_indices .= 0;
        end_indices .= 0;
        batch(record_start_stop!, (range, num_threads()), start_indices, end_indices)
        indices_test_per_thread = end_indices .- start_indices .+ 1
        acceptable_no_per_thread = [fld(range,num_threads()), cld(range,num_threads())]
        @test all(in.(indices_test_per_thread, Ref(acceptable_no_per_thread)))
        @test sum(indices_test_per_thread) == range
        @test length(unique(start_indices)) == num_threads()
        @test length(unique(end_indices)) == num_threads()
    end
end

@testset "!isbits args" begin
    println("Running !isbits args test...")
    # Struct and string
    mutable struct TestStruct
        vec::Vector{String}
    end
    vec_length = 20
    ts = TestStruct(["init" for i in 1:vec_length])
    update_text!((ts, val), start, stop) = ts.vec[start:stop] .= val
    batch(update_text!, (vec_length, num_threads()), ts, "new_val")
    @test all(ts.vec .== "new_val")


    struct Issue20
        values::Vector{Float64}
    end

    function issue20!(dest, cache)
        @batch for i in eachindex(dest)
            factor = -cache.a.values[i]
            dest[i] *= factor
        end
    end

    dest = ones(20)
    cache = (; a = Issue20(ones(length(dest))))
    issue20!(dest, cache)
    @test all(dest .≈ -1)
end

@testset "ForwardDiff" begin
    x = randn(800);
    dxref = similar(x);
    dx = similar(x);
    f(x) = -sum(sum ∘ sincos, x)
    println("Running threaded ForwardDiff test...")
    Polyester.threaded_gradient!(f, dx, x, ForwardDiff.Chunk(8));
    ForwardDiff.gradient!(dxref, f, x, ForwardDiff.GradientConfig(f, x, ForwardDiff.Chunk(8), nothing));
    @test dx == dxref

    dx .= NaN;
    batch((length(x), max(1,num_threads()>>1), 2), dx, x) do (dx,x), start, stop
        Polyester.threaded_gradient!(f, view(dx, start%Int:stop%Int), view(x, start%Int:stop%Int), ForwardDiff.Chunk(8))
    end;
    @test dx ≈ dxref
end

@testset "Non-UnitRange loops" begin
  u = randn(10,100);
  x = view(u,1:5,:);
  xref = 2 .* x;
  @batch for i in eachindex(x)
    x[i] *= 2.0
  end
  arrayofarrays = collect(eachcol(x));
  @batch for x in arrayofarrays
    x .*= 2.0
  end
  @test reduce(hcat, arrayofarrays) == (xref .*= 2)
end

println("Issue 245...")

import Polyester: splitloop, combine, NoLoop, @batch
using Test

struct LazyTree{T}
  t::T
end

Base.getindex(lt::LazyTree, row::Int) = lt.t[row]
Base.length(lt::LazyTree) = length(lt.t)
Base.lastindex(lt::LazyTree) = length(lt)
Base.eachindex(lt::LazyTree) = 1:lastindex(lt)
splitloop(e::Base.Iterators.Enumerate{LazyTree{T}}) where T = NoLoop(), eachindex(e.itr), e
combine(e::Iterators.Enumerate{LazyTree{T}}, ::NoLoop, j) where T =  @inbounds e[j]
Base.getindex(e::Iterators.Enumerate{LazyTree{T}}, row::Int) where T = (row, first(iterate(e.itr, row)))
function Base.iterate(tree::LazyTree, idx=1) where {T<:LazyTree}
  idx > length(tree) && return nothing
  return tree.t[idx], idx + 1
end
Base.firstindex(e::Iterators.Enumerate{LazyTree{T}}) where T = firstindex(e.itr)
Base.lastindex(e::Iterators.Enumerate{LazyTree{T}}) where T = lastindex(e.itr)
Base.eachindex(e::Iterators.Enumerate{LazyTree{T}}) where T = eachindex(e.itr)

@testset "unROOT Enumerate interface" begin
  t = LazyTree(collect(2001:3000))
  for i in 1:3
    println("ITER $i")
    inds = [Vector{Int}() for _ in 1:Threads.nthreads()]
    @batch for (i,evt) in enumerate(t)
      push!(inds[Threads.threadid()], i)
    end
    @test sum([length(inds[i] ∩ inds[j]) for i=1:length(inds), j=1:length(inds) if j>i]) == 0
  end
  evt = 5
end

if VERSION ≥ v"1.6"
  println("Package tests complete. Running `Aqua` checks.")
  Aqua.test_all(Polyester)
end

