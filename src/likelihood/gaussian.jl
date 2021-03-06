"""
```julia
GaussianLikelihood(σ²::T=1e-3) #σ² is the variance
```
Gaussian noise :
```math
    p(y|f) = N(y|f,σ²)
```
There is no augmentation needed for this likelihood which is already conjugate to a Gaussian prior
"""
struct GaussianLikelihood{T<:Real, O, A<:AbstractVector{T}} <: RegressionLikelihood{T}
    σ²::A
    opt_noise::O
    θ::A
    function GaussianLikelihood{T}(σ²::T, opt_noise) where {T<:Real}
        new{T,typeof(opt_noise),Vector{T}}([σ²], opt_noise)
    end
    function GaussianLikelihood{T}(
        σ²::T,
        opt_noise,
        θ::A,
    ) where {T<:Real, A<:AbstractVector{T}}
        new{T,typeof(opt_noise),A}(A([σ²]), opt_noise, θ)
    end
end

function GaussianLikelihood(σ²::T = 1e-3; opt_noise = false) where {T<:Real}
    if isa(opt_noise, Bool)
        opt_noise = opt_noise ? ADAM(0.05) : nothing
    end
    GaussianLikelihood{T}(σ², opt_noise)
end

implemented(::GaussianLikelihood, ::Union{<:AnalyticVI,<:Analytic}) = true

function (l::GaussianLikelihood)(y::Real, f::Real)
    Distributions.pdf(Normal(y, sqrt(noise(l))), f)
end

function Distributions.loglikelihood(l::GaussianLikelihood, y::Real, f::Real)
    Distributions.logpdf(Normal(y, sqrt(noise(l))), f)
end

noise(l::GaussianLikelihood) = first(l.σ²)

function Base.show(io::IO, l::GaussianLikelihood)
    print(io, "Gaussian likelihood (σ² = $(noise(l)))")
end

function compute_proba(
    l::GaussianLikelihood{T},
    μ::AbstractVector{<:Real},
    σ²::AbstractVector{<:Real},
) where {T<:Real}
    return μ, σ² .+ noise(l)
end

function init_likelihood(
    likelihood::GaussianLikelihood{T},
    ::Inference,
    ::Int,
    nSamplesUsed::Int,
) where {T}
    return GaussianLikelihood{T}(
        noise(likelihood),
        likelihood.opt_noise,
        fill(inv(noise(likelihood)), nSamplesUsed),
    )
end

function local_updates!(
    l::GaussianLikelihood,
    y::AbstractVector,
    μ::AbstractVector,
    var_f::AbstractVector,
)
    if !isnothing(l.opt_noise)
        grad =
            0.5 * ((sum(abs2, y - μ) + sum(var_f)) / noise(l) - length(y))
        l.σ² .=
            exp.(log.(l.σ²) + Optimise.apply!(l.opt_noise, l.σ², [grad]))
    end
    l.θ .= inv(noise(l))
end

@inline ∇E_μ(
    l::GaussianLikelihood{T},
    ::AOptimizer,
    y::AbstractVector,
) where {T} = (y ./ noise(l),)

@inline ∇E_Σ(
    l::GaussianLikelihood{T},
    ::AOptimizer,
    y::AbstractVector,
) where {T} = (0.5 * l.θ,)

function expec_log_likelihood(
    l::GaussianLikelihood,
    ::AnalyticVI,
    y::AbstractVector,
    μ::AbstractVector,
    diag_cov::AbstractVector,
)
    return -0.5 * (
        length(y) * (log(twoπ) + log(noise(l))) +
        (sum(abs2, y - μ) + sum(diag_cov)) / noise(l)
    )
end

AugmentedKL(::GaussianLikelihood{T}, ::AbstractVector) where {T} = zero(T)
