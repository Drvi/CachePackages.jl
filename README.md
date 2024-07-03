```bash
➜ julia ./example/run_example.jl
### First run which only drops the cache and builds a new one
drop cache: 0.001653 seconds (171 allocations: 19.289 KiB)
workload 1: 0.470546 seconds (363.35 k allocations: 73.899 MiB, 76.99% compilation time: 97% of which was recompilation)
workload 2: 0.142794 seconds (8.78 k allocations: 49.705 MiB, 21.85% compilation time)
workload 3: 0.118556 seconds (1.49 k allocations: 49.279 MiB, 6.78% compilation time)
workload 4: 0.252257 seconds (4.04 M allocations: 158.800 MiB, 13.71% compilation time)

### We load the cache for the 1st time, so we need to compile the pkgimages
load cache: 9.925567 seconds (372.39 k allocations: 23.116 MiB, 0.74% compilation time)
workload 1: 0.148722 seconds (697 allocations: 49.224 MiB, 6.05% compilation time)
workload 2: 0.139328 seconds (412 allocations: 49.211 MiB)
workload 3: 0.140196 seconds (645 allocations: 49.220 MiB, 2.15% compilation time)
workload 4: 0.239988 seconds (4.00 M allocations: 156.021 MiB)

### We load the cache for the 2nd time, so we load the pkgimages
load cache: 0.145278 seconds (255.71 k allocations: 14.386 MiB)
workload 1: 0.148405 seconds (697 allocations: 49.224 MiB, 6.76% compilation time)
workload 2: 0.138678 seconds (412 allocations: 49.211 MiB)
workload 3: 0.139951 seconds (645 allocations: 49.220 MiB, 2.22% compilation time)
workload 4: 0.241254 seconds (4.00 M allocations: 156.021 MiB)
```