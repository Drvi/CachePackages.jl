include("00_common.jl")

@time "drop cache" drop_all_caches()

make_pkgimage_cache(precompiles_path, "0")


@time "workload 1" _load_data(nothing)
make_pkgimage_cache(precompiles_path, "1")

@time "workload 2" _load_data(Int)
make_pkgimage_cache(precompiles_path, "2")

@time "workload 3" _load_data(Float64)
make_pkgimage_cache(precompiles_path, "3")

@time "workload 4" _load_data(String)
make_pkgimage_cache(precompiles_path, "4")
