println("### First run which only drops the cache and builds a new one")
run(`julia --startup-file=no --project=./example --trace-compile=./example/_precompiles.jl "example/01_init_workload.jl"`)

println()
println("### We load the cache for the 1st time, so we need to compile the pkgimages")
run(`julia --startup-file=no --project=./example "example/02_workload.jl"`)

println()
println("### We load the cache for the 2nd time, so we load the pkgimages")
run(`julia --startup-file=no --project=./example "example/02_workload.jl"`)
