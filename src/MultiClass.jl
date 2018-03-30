
#Batch Xtreme Gaussian Process Classifier (no inducing points)

mutable struct MultiClass <: FullBatchModel
    @commonfields
    @functionfields
    @multiclassfields
    @kernelfields
    function MultiClass(X::AbstractArray,y::AbstractArray;Autotuning::Bool=false,optimizer::Optimizer=Adam(),nEpochs::Integer = 200,
                                    kernel=0,noise::Float64=1e-3,AutotuningFrequency::Integer=10,
                                    ϵ::Float64=1e-5,μ_init::Array{Float64,1}=[0.0],VerboseLevel::Integer=0)
            Y,y_map = one_of_K_mapping(y)
            this = new()
            this.ModelType = MultiClassModel
            this.Name = "MultiClass Gaussian Process Classifier"
            initCommon!(this,X,Y,noise,ϵ,nEpochs,VerboseLevel,Autotuning,AutotuningFrequency,optimizer);
            initFunctions!(this);
            initKernel!(this,kernel);
            initMultiClass!(this,y_map,μ_init);
            return this;
    end
end
