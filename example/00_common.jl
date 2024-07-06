using CSV, DataFrames, CachePackages
_load_data(types) = CSV.read(IOBuffer("a,b" * "\n1,2\n3,4" ^ 1000000), DataFrame; types)

cache_path = joinpath("example", "binary_cache")
precompiles_path = joinpath("example", "_precompiles.jl")
mkpath(cache_path)
set_cache_package_path_and_add_it_to_load_path!(cache_path)
GC.enable(false) # make the example more deterministic
