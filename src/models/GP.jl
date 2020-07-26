"""
Class for Gaussian Processes models

```julia
GP(X::AbstractArray{T}, y::AbstractArray, kernel::Kernel;
    noise::Real=1e-5, opt_noise::Bool=true, verbose::Int=0,
    optimiser=ADAM(0.01),atfrequency::Int=1,
    mean::Union{<:Real,AbstractVector{<:Real},PriorMean}=ZeroMean(),
    IndependentPriors::Bool=true,ArrayType::UnionAll=Vector)
```

Argument list :

**Mandatory arguments**

 - `X` : input features, should be a matrix N×D where N is the number of observation and D the number of dimension
 - `y` : input labels, can be either a vector of labels for multiclass and single output or a matrix for multi-outputs (note that only one likelihood can be applied)
 - `kernel` : covariance function, can be either a single kernel or a collection of kernels for multiclass and multi-outputs models

**Keyword arguments**
 - `noise` : Initial noise of the model
 - `opt_noise` : Flag for optimizing the noise σ=Σ(y-f)^2/N
 - `mean` : Option for putting a prior mean
 - `verbose` : How much does the model print (0:nothing, 1:very basic, 2:medium, 3:everything)
- `optimiser` : Optimiser used for the kernel parameters. Should be an Optimiser object from the [Flux.jl](https://github.com/FluxML/Flux.jl) library, see list here [Optimisers](https://fluxml.ai/Flux.jl/stable/training/optimisers/) and on [this list](https://github.com/theogf/AugmentedGaussianProcesses.jl/tree/master/src/inference/optimisers.jl). Default is `ADAM(0.001)`
 - `IndependentPriors` : Flag for setting independent or shared parameters among latent GPs
 - `atfrequency` : Choose how many variational parameters iterations are between hyperparameters optimization
 - `mean` : PriorMean object, check the documentation on it [`MeanPrior`](@ref meanprior)
 - `ArrayType` : Option for using different type of array for storage (allow for GPU usage)
"""
mutable struct GP{
    T<:Real,
    TLikelihood<:Likelihood{T},
    TInference<:Inference{T},
    1,
    TData<:DataContainer,
} <: AbstractGP{T,TLikelihood,TInference,1}
    data::TData
    f::_GP # Vector of latent GPs
    likelihood::TLikelihood
    inference::TInference
    verbose::Int64 #Level of printing information
    atfrequency::Int64
    Trained::Bool
end


function GP(
    X::AbstractArray,
    y::AbstractArray,
    kernel::Kernel;
    noise::Real = 1e-5,
    opt_noise = true,
    verbose::Int = 0,
    optimiser = ADAM(0.01),
    atfrequency::Int = 1,
    mean::Union{<:Real,AbstractVector{<:Real},PriorMean} = ZeroMean(),
    ArrayType::UnionAll = Vector,
) where {T<:Real}
    likelihood = GaussianLikelihood(T(noise), opt_noise = opt_noise)
    inference = Analytic()

    X = wrap_X(X)

    y, nLatent, likelihood = check_data!(X, y, likelihood)
    data = wrap_data(X, y)
    nFeatures = nSamples(data)
    if isa(optimiser, Bool)
        optimiser = optimiser ? ADAM(0.01) : nothing
    end

    latentf = ntuple(_ -> _GP{T}(nFeatures, kernel, mean, optimiser), nLatent)

    likelihood =
        init_likelihood(likelihood, inference, nLatent, nSamples, nFeatures)

    xview = view(X, :)
    yview = view_y(likelihood, y, 1:nSamples)
    inference = init_inference(
        inference,
        nLatent,
        nSamples,
        nSamples,
        nSamples,
        xview,
        yview,
    )

    model = GP{T}(
        data,
        nFeatures,
        nLatent,
        latentf,
        likelihood,
        inference,
        verbose,
        atfrequency,
        false,
    )
    update_parameters!(model)
    setTrained!(model, true)
    return model
end

function Base.show(io::IO, model::GP)
    print(
        io,
        "Gaussian Process with a $(model.likelihood) infered by $(model.inference) ",
    )
end

nLatent(::GP) = 1

get_y(model::GP) = model.inference.yview
get_Z(model::GP) = model.inference.xview
get_Z(model::GP, i::Int) = model.inference.xview

@traitimpl IsFull{GP}

### Special case where the ELBO is equal to the marginal likelihood

objective(m::GP) = log_py(m)

function log_py(m::GP{T}) where {T}
    f = first(m.f)
    return -0.5 * (dot(m.y, f.Σ \ m.y) + logdet(f.Σ) + nFeatures(m) * log(twoπ))
end
