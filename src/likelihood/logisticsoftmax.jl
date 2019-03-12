"""
Softmax likelihood : ``p(y=i|{fₖ}) = exp(fᵢ)/ ∑ exp(fₖ) ``
"""
abstract type AbstractLogisticSoftMaxLikelihood{T<:Real} <: MultiClassLikelihood{T} end

struct AugmentedLogisticSoftMaxLikelihood{T<:Real} <: AbstractLogisticSoftMaxLikelihood{T}
    Y::AbstractVector{BitVector} #Mapping from instances to classes
    class_mapping::AbstractVector{Any} # Classes labels mapping
    ind_mapping::Dict{Any,Int} # Mapping from label to index
    y_class::AbstractVector{Int64} # GP Index for each sample
    c::AbstractVector{AbstractVector{T}} # Second moment of fₖ
    α::AbstractVector{T} # Variational parameter of Gamma distribution
    β::AbstractVector{T} # Variational parameter of Gamma distribution
    θ::AbstractVector{AbstractVector{T}} # Variational parameter of Polya-Gamma distribution
    γ::AbstractVector{AbstractVector{T}} # Variational parameter of Poisson distribution
    function AugmentedLogisticSoftMaxLikelihood{T}() where {T<:Real}
        new{T}()
    end
    function AugmentedLogisticSoftMaxLikelihood{T}(Y::AbstractVector{<:BitVector},
    class_mapping::AbstractVector, ind_mapping::Dict{<:Any,<:Int},y_class::AbstractVector{<:Int}) where {T<:Real}
        new{T}(Y,class_mapping,ind_mapping,y_class)
    end
    function AugmentedLogisticSoftMaxLikelihood{T}(Y::AbstractVector{<:BitVector},
    class_mapping::AbstractVector, ind_mapping::Dict{<:Any,<:Int},y_class::AbstractVector{<:Int},
    c::AbstractVector{<:AbstractVector{<:Real}}, α::AbstractVector{<:Real},
    β::AbstractVector, θ::AbstractVector{<:AbstractVector},γ::AbstractVector{<:AbstractVector{<:Real}}) where {T<:Real}
        new{T}(Y,class_mapping,ind_mapping,y_class,c,α,β,θ,γ)
    end
end

function AugmentedLogisticSoftMaxLikelihood()
    AugmentedLogisticSoftMaxLikelihood{Float64}()
end

isaugmented(::AugmentedLogisticSoftMaxLikelihood{T}) where T = true

function pdf(l::AbstractLogisticSoftMaxLikelihood,f::AbstractVector)
    logisticsoftmax(f)
end


function pdf(l::AbstractLogisticSoftMaxLikelihood,y::Integer,f::AbstractVector)
    logisticsoftmax(f)[y]
end

function Base.show(io::IO,model::AugmentedLogisticSoftMaxLikelihood{T}) where T
    print(io,"Augmented Logistic-softmax likelihood")
end


function init_likelihood(likelihood::AugmentedLogisticSoftMaxLikelihood{T},nLatent::Integer,nSamplesUsed::Integer) where T
    c = [ones(T,nSamplesUsed) for i in 1:nLatent]
    α = nLatent*ones(T,nSamplesUsed)
    β = nLatent*ones(T,nSamplesUsed)
    θ = [abs.(rand(T,nSamplesUsed))*2 for i in 1:nLatent]
    γ = [abs.(rand(T,nSamplesUsed)) for i in 1:nLatent]
    AugmentedLogisticSoftMaxLikelihood{T}(likelihood.Y,likelihood.class_mapping,likelihood.ind_mapping,likelihood.y_class,c,α,β,θ,γ)
end

struct LogisticSoftMaxLikelihood{T<:Real} <: AbstractLogisticSoftMaxLikelihood{T}
    Y::AbstractVector{BitVector} #Mapping from instances to classes
    class_mapping::AbstractVector{Any} # Classes labels mapping
    ind_mapping::Dict{Any,Int} # Mapping from label to index
    y_class::AbstractVector{Int64} #GP Index for each sample
    function LogisticSoftMaxLikelihood{T}() where {T<:Real}
        new{T}()
    end
    function LogisticSoftMaxLikelihood{T}(Y::AbstractVector{<:BitVector},
    class_mapping::AbstractVector, ind_mapping::Dict{<:Any,<:Int},y_class::AbstractVector{<:Int}) where {T<:Real}
        new{T}(Y,class_mapping,ind_mapping,y_class)
    end
end

function LogisticSoftMaxLikelihood()
    LogisticSoftMaxLikelihood{Float64}()
end

function Base.show(io::IO,model::LogisticSoftMaxLikelihood{T}) where T
    print(io,"logistic-softmax likelihood")
end

function init_likelihood(likelihood::LogisticSoftMaxLikelihood{T},nLatent::Integer,nSamplesUsed::Integer) where T
    return likelihood
end

function local_updates!(model::VGP{AugmentedLogisticSoftMaxLikelihood{T},AnalyticInference{T},T,V}) where {T<:Real,V<:AbstractVector{T}}
    model.likelihood.c .= broadcast((Σ::V,μ::V)->sqrt.(Σ.+abs2.(μ)),diag.(model.Σ),model.μ)
    for _ in 1:2
        model.likelihood.γ .= broadcast((c::V,μ::V,ψα::V)->0.5/(model.likelihood.β[1])*exp.(ψα).*safe_expcosh.(-0.5*μ,0.5*c),
                                    model.likelihood.c,model.μ,[digamma.(model.likelihood.α)])
        model.likelihood.α .= 1.0.+(model.likelihood.γ...)
    end
    model.likelihood.θ .= broadcast((y::BitVector,γ::V,c::V)->0.5*(y.+γ)./c.*tanh.(0.5*c),model.likelihood.Y,model.likelihood.γ,model.likelihood.c)
end

function local_updates!(model::SVGP{<:AugmentedLogisticSoftMaxLikelihood{T},AnalyticInference{T},T,V}) where {T<:Real,V<:AbstractVector{T}}
    model.likelihood.c .= broadcast((μ::V,Σ::Symmetric{T,Matrix{T}},κ::Matrix{T},K̃::V)->sqrt.(K̃+opt_diag(κ*Σ,κ)+abs2.(κ*μ)),
                                    model.μ,model.Σ,model.κ,model.K̃)
    for _ in 1:5
        model.likelihood.γ .= broadcast((c::V,κμ::V,ψα::V)->(0.5/(model.likelihood.β[1]))*exp.(ψα).*safe_expcosh.(-0.5*κμ,0.5*c),
                                    model.likelihood.c,model.κ.*model.μ,[digamma.(model.likelihood.α)])
        model.likelihood.α .= 1.0.+(model.likelihood.γ...)
    end
    model.likelihood.θ .= broadcast((y::BitVector,γ::V,c::V)->0.5.*(y[model.inference.MBIndices]+γ)./c.*tanh.(0.5.*c),
                                    model.likelihood.Y,model.likelihood.γ,model.likelihood.c)
    return nothing
end

function sample_local!(model::VGP{<:AugmentedLogisticSoftMaxLikelihood,<:GibbsSampling})
    if model.inference.nIter <= 1
        # model.likelihood.α .= 10.0.*model.likelihood.α./model.likelihood.β
    end
    model.likelihood.γ .= broadcast(μ::AbstractVector{<:Real}->rand.(Poisson.(0.5*model.likelihood.α.*safe_expcosh.(-0.5*μ,0.5*μ))), model.μ)
    model.likelihood.α .= rand.(Gamma.(1.0.+(model.likelihood.γ...),1.0./model.likelihood.β))
    model.likelihood.θ .= broadcast((y::BitVector,γ::AbstractVector{<:Real},μ::AbstractVector{<:Real})->PolyaGammaDist().draw.(y.+γ,μ),model.likelihood.Y,model.likelihood.γ,model.μ)
    return nothing
end

function sample_global!(model::VGP{<:AugmentedLogisticSoftMaxLikelihood,<:GibbsSampling})
    model.Σ .= inv.(Symmetric.(Diagonal.(model.likelihood.θ).+model.invKnn))
    model.μ .= rand.(MvNormal.(0.5.*model.Σ.*(model.likelihood.Y.-model.likelihood.γ),model.Σ))
    return nothing
end


""" Return the gradient of the expectation for latent GP `index` """
function expec_μ(model::VGP{<:AugmentedLogisticSoftMaxLikelihood},index::Int)
    0.5.*(model.likelihood.Y[index]-model.likelihood.γ[index])
end

function ∇μ(model::VGP{<:AugmentedLogisticSoftMaxLikelihood})
    0.5.*(model.likelihood.Y.-model.likelihood.γ)
end

""" Return the gradient of the expectation for latent GP `index` """
function expec_μ(model::SVGP{<:AugmentedLogisticSoftMaxLikelihood},index::Integer)
    0.5.*(model.likelihood.Y[index][model.inference.MBIndices]-model.likelihood.γ[index])
end

function ∇μ(model::SVGP{<:AugmentedLogisticSoftMaxLikelihood})
    0.5.*(getindex.(model.likelihood.Y,[model.inference.MBIndices]).-model.likelihood.γ)
end

function expec_Σ(model::GP{<:AugmentedLogisticSoftMaxLikelihood},index::Integer)
    0.5.*model.likelihood.θ[index]
end

function ∇Σ(model::GP{AugmentedLogisticSoftMaxLikelihood{T}}) where {T<:Real}
    Diagonal{T}.(0.5.*model.likelihood.θ)
end

function ELBO(model::GP{<:AugmentedLogisticSoftMaxLikelihood})
    return expecLogLikelihood(model) - GaussianKL(model) - GammaImproperKL(model) - PoissonKL(model) - PolyaGammaKL(model)
end

function expecLogLikelihood(model::VGP{<:AugmentedLogisticSoftMaxLikelihood})
    model.likelihood.c .= broadcast((Σ,μ)->sqrt.(Σ.+abs2.(μ)),diag.(model.Σ),model.μ)
    tot = -model.nSample*logtwo
    tot += -sum(sum.(model.likelihood.γ))*logtwo
    tot +=  0.5*sum(broadcast((y,μ,γ,θ,c)->sum(μ.*(y-γ)-θ.*abs2.(c)),
                    model.likelihood.Y,model.μ,model.likelihood.γ,model.likelihood.θ,model.likelihood.c))
    return tot
end

function expecLogLikelihood(model::SVGP{<:AugmentedLogisticSoftMaxLikelihood})
    model.likelihood.c .= broadcast((μ::AbstractVector,Σ::AbstractMatrix,κ::AbstractMatrix,K̃::AbstractVector)->sqrt.(K̃+opt_diag(κ*Σ,κ)+abs2.(κ*μ)),
                                    model.μ,model.Σ,model.κ,model.K̃)
    tot = -model.inference.nSamplesUsed*logtwo
    tot += -sum(sum.(model.likelihood.γ))*logtwo
    tot += 0.5*sum(broadcast((y,κμ,γ,θ,c)->sum((κμ).*(y[model.inference.MBIndices]-γ)-θ.*abs2.(c)),
                    model.likelihood.Y,model.κ.*model.μ,model.likelihood.γ,model.likelihood.θ,model.likelihood.c))
    return model.inference.ρ*tot
end

function grad_samples(model::GP{<:LogisticSoftMaxLikelihood,<:NumericalInference,T},samples::AbstractMatrix{T},index::Integer) where {T<:Real}
    class = model.likelihood.y_class[index]::Int64
    grad_μ = zeros(T,model.nLatent)
    grad_Σ = zeros(T,model.nLatent)
    g_μ = similar(grad_μ)
    nSamples = size(samples,1)
    @views @inbounds for i in 1:nSamples
        σ = logistic.(samples[i,:])
        samples[i,:]  .= logisticsoftmax(samples[i,:])
        s = samples[i,class]
        g_μ .= grad_logisticsoftmax(samples[i,:],σ,class)/s
        grad_μ += g_μ
        grad_Σ += diaghessian_logisticsoftmax(samples[i,:],σ,class)/s - abs2.(g_μ)
    end
    for k in 1:model.nLatent
        model.inference.∇μE[k][index] = grad_μ[k]/nSamples
        model.inference.∇ΣE[k][index] = 0.5.*grad_Σ[k]/nSamples
    end
end

function log_like_samples(model::GP{<:LogisticSoftMaxLikelihood,<:Inference,T},samples::AbstractMatrix,index::Integer) where {T<:Real}
    class = model.likelihood.y_class[index]
    nSamples = size(samples,1)
    loglike = zero(T)
    for i in 1:nSamples
        σ = logistic.(samples[i,:])
        loglike += log(σ[class])-log(sum(σ))
    end
    return loglike/nSamples
end

function remove_augmentation(l::Type{AugmentedLogisticSoftMaxLikelihood{T}}) where T
    return LogisticSoftMaxLikelihood{T}(l.Y,l.class_mapping,l.ind_mapping)
end

function grad_logisticsoftmax(s::AbstractVector{<:Real},σ::AbstractVector{<:Real},i::Integer)
    s[i]*(δ.(i,eachindex(σ)).-s).*(1.0.-σ)
end

function diaghessian_logisticsoftmax(s::AbstractVector{<:Real},σ::AbstractVector{<:Real},i::Integer)
    s[i]*(1.0.-σ).*(
    abs2.(δ.(i,eachindex(σ))-s).*(1.0.-σ)
    -s.*(1.0.-s).*(1.0.-σ)
    -σ.*(δ.(i,eachindex(σ))-s))
end

function hessian_logisticsoftmax(s::AbstractVector{T},σ::AbstractVector{T},i::Integer) where {T<:Real}
    m = length(s)
    hessian = zeros(T,m,m)
    @inbounds for j in 1:m
        for k in 1:m
            hessian[j,k] = (1-σ[j])*s[i]*(
            (δ(i,k)-s[k])*(1.0-σ[k])*(δ(i,j)-s[j])
            -s[j]*(δ(j,k)-s[k])*(1.0-σ[k])
            -δ(k,j)*σ[j]*(δ(i,j)-s[j]))
        end
    end
    return hessian
end
