"""
    flatten(x)

If `x` is an array of arrays, flatten into a single array whose dimensions are ordered with
dimensions of the outermost container first and innermost container last.
"""
flatten(x) = x
flatten(x::AbstractArray{<:Number}) = convert(Array, x)
function flatten(x::AbstractArray{S}) where {T<:Number,N,S<:AbstractArray{T,N}}
    ret = Array{T}(undef, (size(x)..., size(x[1])...))
    for k in keys(x)
        setindex!(ret, x[k], k, (Colon() for _ in 1:N)...)
    end
    return ret
end

"""
    namedtuple_of_arrays(x::NamedTuple) -> NamedTuple
    namedtuple_of_arrays(x::AbstractArray{NamedTuple}) -> NamedTuple
    namedtuple_of_arrays(x::AbstractArray{AbstractArray{<:NamedTuple}}) -> NamedTuple

Given a container of `NamedTuple`s, concatenate them, using the container dimensions as the
dimensions of the resulting arrays.

# Examples

```@example
using ArviZ
nchains, ndraws = 4, 100
data = [(x=rand(), y=randn(2), z=randn(2, 3)) for _ in 1:nchains, _ in 1:ndraws];
ntarray = ArviZ.namedtuple_of_arrays(data);
```
"""
namedtuple_of_arrays(x::NamedTuple) = map(flatten, x)
namedtuple_of_arrays(x::AbstractArray) = namedtuple_of_arrays(namedtuple_of_arrays.(x))
function namedtuple_of_arrays(x::AbstractArray{<:NamedTuple{K}}) where {K}
    return mapreduce(merge, K) do k
        v = flatten.(getproperty.(x, k))
        return (; k => flatten(v))
    end
end

function package_version(pkg::Module)
    isdefined(Base, :pkgversion) && return Base.pkgversion(pkg)
    project = joinpath(dirname(dirname(pathof(pkg))), "Project.toml")
    toml = read(project, String)
    m = match(r"(*ANYCRLF)^version\s*=\s\"(.*)\"$"m, toml)
    return VersionNumber(m[1])
end

rekey(d, keymap) = Dict(get(keymap, k, k) => d[k] for k in keys(d))
function rekey(d::NamedTuple, keymap)
    new_keys = map(k -> get(keymap, k, k), keys(d))
    return NamedTuple{new_keys}(values(d))
end
