@testset "likelihood" begin
    struct NewLikelihood{T} <: AGP.Likelihood{T} end
    @test_throws ErrorException NewLikelihood{Float64}()(rand(), rand())
    @test length(NewLikelihood{Float64}()) == 1
end
