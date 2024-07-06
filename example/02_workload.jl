include("00_common.jl")

@time "load cache" load_all_caches()

@time "workload 1" _load_data(nothing)
@time "workload 2" _load_data(Int)
@time "workload 3" _load_data(Float64)
@time "workload 4" _load_data(String)
