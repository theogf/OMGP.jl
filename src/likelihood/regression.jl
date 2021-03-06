abstract type RegressionLikelihood{T<:Real} <: Likelihood{T} end

include("gaussian.jl")
include("studentt.jl")
include("laplace.jl")
include("heteroscedastic.jl")
include("matern.jl")

### Return the labels in a vector of vectors for multiple outputs
function treat_labels!(
    y::AbstractVector{T},
    likelihood::L,
) where {T,L<:RegressionLikelihood}
    @assert T <: Real "For regression target(s) should be real valued"
    return y, 1, likelihood
end

predict_y(l::RegressionLikelihood, μ::AbstractVector{<:Real}) = μ
predict_y(l::RegressionLikelihood, μ::AbstractVector{<:AbstractVector}) =
    first(μ)
