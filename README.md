```bash
➜ julia ./example/run_example.jl
### First run which only drops the cache and builds a new one
drop cache: 0.002082 seconds (171 allocations: 19.289 KiB)
workload 1: 0.467809 seconds (363.35 k allocations: 73.903 MiB, 76.94% compilation time: 97% of which was recompilation)
workload 2: 0.138096 seconds (8.78 k allocations: 49.705 MiB, 22.29% compilation time)
workload 3: 0.114149 seconds (1.49 k allocations: 49.279 MiB, 7.12% compilation time)
workload 4: 0.244066 seconds (4.04 M allocations: 158.800 MiB, 13.99% compilation time)

### We load the cache for the 1st time, so we need to compile the pkgimages
load cache: 3.357861 seconds (320.33 k allocations: 19.510 MiB, 0.76% compilation time)
workload 1: 0.150228 seconds (697 allocations: 49.224 MiB, 6.20% compilation time)
workload 2: 0.137583 seconds (412 allocations: 49.211 MiB)
workload 3: 0.141016 seconds (645 allocations: 49.220 MiB, 2.31% compilation time)
workload 4: 0.239699 seconds (4.00 M allocations: 156.021 MiB)

### We load the cache for the 2nd time, so we load the pkgimages
load cache: 0.147548 seconds (253.52 k allocations: 14.661 MiB)
workload 1: 0.149391 seconds (697 allocations: 49.224 MiB, 6.01% compilation time)
workload 2: 0.140333 seconds (412 allocations: 49.211 MiB)
workload 3: 0.140037 seconds (645 allocations: 49.220 MiB, 2.33% compilation time)
workload 4: 0.241620 seconds (4.00 M allocations: 156.021 MiB)
```