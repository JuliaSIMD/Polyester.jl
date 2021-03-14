println("Starting tests...")
using CheapThreads, Aqua, ForwardDiff
using Test

@testset "Range Map" begin
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

    x = rand(1024); y = rand(length(x)); z = similar(x);
    foo(x,y) = exp(-0.5abs2(x-y))
    println("Running `tmap!` test...")
    @test tmap!(foo, z, x, y) ≈ foo.(x, y)

    # TODO: why does this crash Julia?
    # function slow_task!((x, digits, n), j, k)
    #     start = 1 + (n * (j - 1)) ÷ num_threads()
    #     stop =  (n* k) ÷ num_threads()
    #     target = 0.0
    #     for i ∈ start:stop
    #         target += occursin(digits, string(i)) ? 0.0 : 1.0 / i
    #     end
    #     x[1,j] = target
    # end
    # function slow_cheap(n, digits)
    #     x = zeros(8, num_threads())
    #     batch(slow_task!, (num_threads(), num_threads()), x, digits, n)
    #     sum(@view(x[1,1:end]))
    # end
    # slow_cheap(1000, "9")
end

@testset "ForwardDiff" begin
    x = randn(80);
    dxref = similar(x);
    dx = similar(x);
    f(x) = -sum(sum ∘ sincos, x)
    println("Running threaded ForwardDiff test...")
    CheapThreads.threaded_gradient!(f, dx, x, ForwardDiff.Chunk(8))
    ForwardDiff.gradient!(dxref, f, x, ForwardDiff.GradientConfig(f, x, ForwardDiff.Chunk(8), nothing))
    @test dx == dxref
end

println("Package tests complete. Running `Aqua` checks.")
Aqua.test_all(CheapThreads)

