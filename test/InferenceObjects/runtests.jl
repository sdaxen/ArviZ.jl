using ArviZ.InferenceObjects, Test

@testset "InferenceObjects" begin
    include("dataset.jl")
    include("inference_data.jl")
    include("convert_dataset.jl")
end
