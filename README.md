```bash
julia ./example/run_example.jl

### First run which only drops the cache and builds a new one
drop cache: 0.002968 seconds (171 allocations: 19.289 KiB)
workload 1: 0.380169 seconds (363.21 k allocations: 24.729 MiB, 99.76% compilation time: 98% of which was recompilation)
workload 2: 0.033720 seconds (8.64 k allocations: 547.836 KiB, 97.79% compilation time)
workload 3: 0.007741 seconds (1.34 k allocations: 111.719 KiB, 92.33% compilation time)
workload 4: 0.041449 seconds (43.51 k allocations: 2.906 MiB, 98.13% compilation time)

### We load the cache for the 1st time, so we need to compile the pkgimages
load cache: 9.766075 seconds (370.93 k allocations: 23.037 MiB, 0.78% compilation time)
workload 1: 0.009555 seconds (554 allocations: 54.891 KiB, 92.15% compilation time)
workload 2: 0.000446 seconds (269 allocations: 41.945 KiB)
workload 3: 0.003636 seconds (502 allocations: 51.688 KiB, 84.85% compilation time)
workload 4: 0.003772 seconds (258 allocations: 41.641 KiB, 86.40% compilation time)

### We load the cache for the 2nd time, so we load the pkgimages
load cache: 0.155077 seconds (253.88 k allocations: 14.261 MiB)
workload 1: 0.010101 seconds (554 allocations: 54.891 KiB, 92.47% compilation time)
workload 2: 0.000408 seconds (269 allocations: 41.938 KiB)
workload 3: 0.010675 seconds (502 allocations: 51.688 KiB, 94.31% compilation time)
workload 4: 0.003379 seconds (258 allocations: 41.648 KiB, 86.03% compilation time)
```