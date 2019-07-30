"""
**QuadratureVI**

Variational Inference solver by approximating gradients via numerical integration via Quadrature

```julia
QuadratureVI(ϵ::T=1e-5,nGaussHermite::Integer=20,optimizer::Optimizer=Adam(α=0.1))
```

**Keyword arguments**

    - `ϵ::T` : convergence criteria
    - `nGaussHermite::Int` : Number of points for the integral estimation
    - `optimizer::Optimizer` : Optimizer used for the variational updates. Should be an Optimizer object from the [GradDescent.jl](https://github.com/jacobcvt12/GradDescent.jl) package. Default is `Adam()`
"""
mutable struct QuadratureVI{T<:Real} <: NumericalVI{T}
    ϵ::T #Convergence criteria
    nIter::Integer #Number of steps performed
    optimizer_η₁::LatentArray{Optimizer} #Learning rate for stochastic updates
    optimizer_η₂::LatentArray{Optimizer} #Learning rate for stochastic updates
    nPoints::Int64 #Number of points for the quadrature
    nodes::Vector{T}
    weights::Vector{T}
    Stochastic::Bool #Use of mini-batches
    nSamples::Int64 #Number of samples of the data
    nSamplesUsed::Int64 #Size of mini-batches
    MBIndices::Vector #Indices of the minibatch
    ρ::T #Stochastic Coefficient
    HyperParametersUpdated::Bool #To know if the inverse kernel matrix must updated
    ∇η₁::LatentArray{Vector{T}}
    ∇η₂::LatentArray{Symmetric{T,Matrix{T}}}
    ∇μE::LatentArray{Vector{T}}
    ∇ΣE::LatentArray{Vector{T}}
    function QuadratureVI{T}(ϵ::T,nPoints::Integer,nIter::Integer,optimizer::Optimizer,Stochastic::Bool,nSamplesUsed::Integer=1) where T
        gh = gausshermite(nPoints)
        return new{T}(ϵ,nIter,[optimizer],[optimizer],nPoints,gh[1],gh[2]./sqrtπ,Stochastic,1,nSamplesUsed)
    end
end

function QuadratureVI(;ϵ::T=1e-5,nGaussHermite::Integer=1000,optimizer::Optimizer=Adam(α=0.01)) where {T<:Real}
    QuadratureVI{T}(ϵ,nGaussHermite,0,optimizer,false)
end


"""
**QuadratureSVI**

Stochastic Variational Inference solver by approximating gradients via numerical integration via Quadrature

```julia
QuadratureSVI(nMinibatch::Integer;ϵ::T=1e-5,nGaussHermite::Integer=20,optimizer::Optimizer=Adam(α=0.1))
```
    -`nMinibatch::Integer` : Number of samples per mini-batches

**Keyword arguments**

    - `ϵ::T` : convergence criteria, which can be user defined
    - `nGaussHermite::Int` : Number of points for the integral estimation (for the QuadratureVI)
    - `optimizer::Optimizer` : Optimizer used for the variational updates. Should be an Optimizer object from the [GradDescent.jl](https://github.com/jacobcvt12/GradDescent.jl) package. Default is `Adam()`
"""
function QuadratureSVI(nMinibatch::Integer;ϵ::T=1e-5,nGaussHermite::Integer=20,optimizer::Optimizer=Adam(α=0.1)) where {T<:Real}
    QuadratureVI{T}(ϵ,nGaussHermite,0,optimizer,false,nMinibatch)
end

function expecLogLikelihood(model::VGP{T,L,<:QuadratureVI}) where {T,L}
    tot = 0.0
    for k in 1:model.nLatent
        for i in 1:model.nSample
            expectation(x->logpdf(model.likelihood,model.y[k][i],x),Normal(model.μ[k][i],sqrt(model.Σ[k][i,i])))
        end
    end
    return tot
end


function compute_grad_expectations!(model::VGP{T,L,<:QuadratureVI}) where {T,L}
    for k in 1:model.nLatent
        for i in 1:model.nSample
            model.inference.∇μE[k][i], model.inference.∇ΣE[k][i] = grad_quad(model.likelihood, model.y[k][i], model.μ[k][i], model.Σ[k][i,i],model.inference)
        end
    end
end

function compute_grad_expectations!(model::SVGP{T,L,<:QuadratureVI}) where {T,L}
    μ = model.κ.*model.μ; Σ = opt_diag(model.κ.*model.Σ,model.κ)
    for k in 1:model.nLatent
        for i in 1:model.nSample
            model.inference.∇μE[k][i], model.inference.∇ΣE[k][i] = grad_quad(model.likelihood, model.y[k][i], μ[k][i], Σ[k][i,i], model.inference.nPoints)
        end
    end
end

function grad_quad(likelihood::Likelihood{T},y::Real,μ::Real,σ²::Real,inference::Inference) where {T<:Real}
    # e = expectation(Normal(μ,sqrt(σ²)),n=inference.nPoints)
    # dμ = e(x->grad_log_pdf_μ(likelihood,y,x))
    # dΣ = 0.5*e(x->grad_log_pdf_Σ(likelihood,y,x))

    nodes = inference.nodes*sqrt2*sqrt(σ²) .+ μ
    dμ = dot(inference.weights,(x->grad_log_pdf_μ(likelihood,y,x)).(nodes))
    dΣ = 0.5*dot(inference.weights,(x->grad_log_pdf_Σ(likelihood,y,x)).(nodes))
    # p = e(x->pdf(likelihood,y,x))
    return dμ::T, dΣ::T
end


function compute_log_expectations(model::VGP{T,L,<:QuadratureVI}) where {T,L}
end


function compute_log_expectations(model::SVGP{T,L,<:QuadratureVI}) where {T,L}
end
