```bash
➜ julia ./example/run_example.jl
### First run which only drops the cache and builds a new one
drop cache: 0.001623 seconds (171 allocations: 19.289 KiB)
workload 1: 0.523348 seconds (363.35 k allocations: 73.899 MiB, 10.97% gc time, 69.44% compilation time: 97% of which was recompilation)
workload 2: 0.142453 seconds (8.78 k allocations: 49.705 MiB, 2.14% gc time, 22.62% compilation time)
workload 3: 0.116944 seconds (1.49 k allocations: 49.279 MiB, 1.15% gc time, 7.34% compilation time)
workload 4: 0.288068 seconds (4.04 M allocations: 158.800 MiB, 15.13% gc time, 12.16% compilation time)

### We load the cache for the 1st time, so we need to compile the pkgimages
load cache: 9.497296 seconds (372.21 k allocations: 23.110 MiB, 0.75% compilation time)
workload 1: 0.154310 seconds (697 allocations: 49.224 MiB, 4.50% gc time, 6.27% compilation time)
workload 2: 0.136616 seconds (412 allocations: 49.211 MiB, 1.90% gc time)
workload 3: 0.141347 seconds (645 allocations: 49.220 MiB, 3.24% gc time, 2.39% compilation time)
workload 4: 0.345853 seconds (4.00 M allocations: 156.021 MiB, 32.82% gc time)

### We load the cache for the 2nd time, so we load the pkgimages
load cache: 0.144838 seconds (255.65 k allocations: 14.383 MiB)
workload 1: 0.154608 seconds (697 allocations: 49.224 MiB, 4.16% gc time, 6.23% compilation time)
workload 2: 0.191134 seconds (412 allocations: 49.211 MiB, 28.86% gc time)
workload 3: 0.189825 seconds (645 allocations: 49.220 MiB, 27.67% gc time, 1.60% compilation time)
workload 4: 0.285878 seconds (4.00 M allocations: 156.021 MiB, 18.47% gc time)
```