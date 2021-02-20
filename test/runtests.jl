using CheapThreads, Aqua
using Test

@testset "CheapThreads.jl" begin
    Aqua.test_all(CheapThreads)
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
    @test tmap!(foo, z, x, y) ≈ foo.(x, y)

end
