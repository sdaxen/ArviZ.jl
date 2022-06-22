const SUPPORTED_GROUPS = Symbol[]
const SUPPORTED_GROUPS_DICT = Dict{Symbol,Int}()

"""
    InferenceData(; kwargs...)

Container for inference data storage using DimensionalData.

`InferenceData` can be constructed either from an `arviz.InferenceData` or from multiple
[`Dataset`](@ref)s assigned to groups specified as `kwargs`.

Instead of directly creating an `InferenceData`, use the exported `from_xyz` functions or
[`convert_to_inference_data`](@ref).
"""
struct InferenceData
    groups::Dict{Symbol,Dataset}
end
InferenceData(; kwargs...) = InferenceData(Dict(kwargs))
InferenceData(data::InferenceData) = data

InferenceData(; kwargs...) = reorder_groups!(arviz.InferenceData(; kwargs...))
@inline InferenceData(data::InferenceData) = data

@inline PyObject(data::InferenceData) = getfield(data, :o)

Base.convert(::Type{InferenceData}, obj::PyObject) = InferenceData(obj)
Base.convert(::Type{InferenceData}, obj) = convert_to_inference_data(obj)
Base.convert(::Type{InferenceData}, obj::InferenceData) = obj

Base.hash(data::InferenceData) = hash(PyObject(data))
Base.propertynames(data::InferenceData) = sort!(collect(keys(groups(data))))

Base.hasproperty(data::InferenceData, k::Symbol) = hasgroup(data, k)

Base.getproperty(data::InferenceData, k::Symbol) = getindex(groups(data), k)

function Base.setproperty!(data::InferenceData, k::Symbol, ds::Dataset)
    groups(data)[k] = ds
    return ds
end

Base.delete!(data::InferenceData, name) = PyObject(data).__delattr__(string(name))

@forwardfun extract_dataset

function (data1::InferenceData + data2::InferenceData)
    return InferenceData(PyObject(data1) + PyObject(data2))
end

function Base.show(io::IO, data::InferenceData)
    out = pycall(pybuiltin("str"), String, data)
    out = replace(out, "Inference data" => "InferenceData")
    print(io, out)
    return nothing
end
function Base.show(io::IO, ::MIME"text/html", data::InferenceData)
    obj = PyObject(data)
    (:_repr_html_ in propertynames(obj)) || return show(io, data)
    out = obj._repr_html_()
    out = replace(out, r"arviz.InferenceData" => "InferenceData")
    out = replace(out, r"(<|&lt;)?xarray.Dataset(>|&gt;)?" => "Dataset (xarray.Dataset)")
    print(io, out)
    return nothing
end

"""
    groupnames(data::InferenceData) -> Vector{Symbol}

Get the names of the groups (datasets) in `data`.
"""
function groupnames(data::InferenceData)
    return sort!(collect(keys(groups(data))); by=k -> SUPPORTED_GROUPS_DICT[k])
end

"""
    groups(data::InferenceData) -> Dict{Symbol,Dataset}

Get the groups in `data` as a dictionary mapping names to datasets.
"""
groups(data::InferenceData) = getfield(data, :groups)

Base.isempty(data::InferenceData) = isempty(groupnames(data))

@forwardfun convert_to_inference_data

convert_to_inference_data(::Nothing; kwargs...) = InferenceData()

function convert_to_dataset(data::InferenceData; group=:posterior, kwargs...)
    group = Symbol(group)
    dataset = getproperty(data, group)
    return dataset
end

@forwardfun load_arviz_data

@forwardfun to_netcdf
@forwardfun from_netcdf
@forwardfun from_dict
@forwardfun from_cmdstan
@forwardfun from_cmdstanpy
@forwardfun from_emcee
@forwardfun from_pymc3
@forwardfun from_pyro
@forwardfun from_numpyro
@forwardfun from_pystan
@forwardfun from_tfp

# A more flexible form of `from_dict`
# Internally calls `dict_to_dataset`
function _from_dict(posterior=nothing; attrs=Dict(), coords=nothing, dims=nothing, dicts...)
    dicts = (posterior=posterior, dicts...)

    datasets = []
    for (name, dict) in pairs(dicts)
        (dict === nothing || isempty(dict)) && continue
        dataset = dict_to_dataset(dict; attrs, coords, dims)
        push!(datasets, name => dataset)
    end

    idata = InferenceData(; datasets...)
    return idata
end

@doc forwarddoc(:concat) concat

function concat(data::InferenceData...; kwargs...)
    return arviz.concat(data...; inplace=false, kwargs...)
end

Docs.getdoc(::typeof(concat)) = forwardgetdoc(:concat)

@doc doc"""
    concat!(data1::InferenceData, data::InferenceData...; kwargs...) -> InferenceData

In-place version of `concat`, where `data1` is modified to contain the concatenation of
`data` and `args`. See [`concat`](@ref) for a description of `kwargs`.
"""
concat!

function concat!(data::InferenceData, other_data::InferenceData...; kwargs...)
    arviz.concat(data, other_data...; inplace=true, kwargs...)
    return data
end
concat!(; kwargs...) = InferenceData()

function rekey(data::InferenceData, keymap)
    keymap = Dict([Symbol(k) => Symbol(v) for (k, v) in keymap])
    dnames = groupnames(data)
    data_new = InferenceData[]
    for k in dnames
        knew = get(keymap, k, k)
        push!(data_new, InferenceData(; knew => getproperty(data, k)))
    end
    return concat(data_new...)
end

function reorder_groups!(data::InferenceData; group_order=SUPPORTED_GROUPS)
    group_order = map(Symbol, group_order)
    names = groupnames(data)
    sorted_names = filter(n -> n ∈ names, group_order)
    other_names = filter(n -> n ∉ sorted_names, names)
    obj = PyObject(data)
    setproperty!(obj, :_groups, string.([sorted_names; other_names]))
    return data
end
