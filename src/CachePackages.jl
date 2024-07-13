module CachePackages

using Pkg, TOML, UUIDs, Dates

const CACHE_PACKAGES_LOAD_PATH = Ref{String}()
const CACHE_PACKAGES_DEPOT_PATH = Ref{String}()
const MAX_CONCURRENT_PRECOMPILES = Ref{Int}()
const CACHE_PACKAGES_LOAD_PATH_LOCK = ReentrantLock()
const CACHE_PACKAGE_NAME_PREFIX = "Cache"

function __init__()
    path = mkpath(joinpath(first(Base.DEPOT_PATH), "cache_packages"))
    set_cache_package_path_and_add_it_to_load_path!(path)
    CACHE_PACKAGES_DEPOT_PATH[] = DEPOT_PATH[1] # TODO: fully support separate depots
    MAX_CONCURRENT_PRECOMPILES[] = 1 #Threads.nthreads(:default)
end

export set_cache_package_path_and_add_it_to_load_path!, make_pkgimage_cache, precompile_all_caches, load_all_caches, drop_all_caches, list_all_caches

function set_cache_package_path_and_add_it_to_load_path!(path)
    @lock CACHE_PACKAGES_LOAD_PATH_LOCK begin
        if isassigned(CACHE_PACKAGES_LOAD_PATH)
            i = findall(isequal(CACHE_PACKAGES_LOAD_PATH[]), LOAD_PATH)
            isempty(i) || splice!(LOAD_PATH, i)
        end
        apath = abspath(path)
        CACHE_PACKAGES_LOAD_PATH[] = apath
        apath in LOAD_PATH || push!(LOAD_PATH, apath) # Split this into two methods?
    end
    return nothing
end

function list_all_caches(cache_load_path=CACHE_PACKAGES_LOAD_PATH[]; join=false)
    if join
        return filter!(_is_cache_pkg_path, readdir(cache_load_path, join=true))
    else
        return filter!(p->startswith(p, CACHE_PACKAGE_NAME_PREFIX), readdir(cache_load_path, join=false))
    end
end

_now() = Dates.format(Dates.now(), "yyyymmddHHMMSSsss")
_is_cache_pkg_path(path) = isdir(path) && startswith(basename(path), CACHE_PACKAGE_NAME_PREFIX)

function make_pkgimage_cache(
    precompiles_path::Union{Nothing,AbstractString}=nothing,
    suffix=_now();
    precompiles_filter=Returns(true),
    maxsize::Integer=typemax(Int),
    dedupe=true,
    project=Base.active_project(),
    cache_load_path=CACHE_PACKAGES_LOAD_PATH[]
)
    maxsize < 1 && ArgumentError("`maxsize` must be a positive integer")
    if isnothing(precompiles_path)
        trace_compile_ptr = Base.JLOptions().trace_compile
        trace_compile_ptr == C_NULL && ArgumentError("No `precompiles_path` provided and `--trace-compile` is not set")
        precompiles_path = unsafe_string(trace_compile_ptr)
    end
    cache_pkg_name = string(CACHE_PACKAGE_NAME_PREFIX, string(suffix))

    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    isfile(precompiles_path) || error("Precompiles file cannot be found at path `$precompiles_path`")

    current_cache_paths = readdir(cache_load_path, join=true)
    cache_path = joinpath(cache_load_path, cache_pkg_name)
    any(startswith(cache_path), current_cache_paths) && error("Cache with suffix `$suffix` already exists at `$(joinpath(cache_load_path, cache_pkg_name))`")

    # TODO: Validate the precompile statements
    precompiles_dict = Dict(
        precompile => Int32(i)
        for (i, precompile)
        in enumerate(Iterators.map(strip, eachline(precompiles_path)))
        if precompiles_filter(precompile)
    )

    if dedupe
        for other_cache_pkg_name in current_cache_paths
            isdir(other_cache_pkg_name) || continue
            startswith(basename(other_cache_pkg_name), CACHE_PACKAGE_NAME_PREFIX) || continue
            for other_precompile in eachline(joinpath(other_cache_pkg_name, "src", "precompiles.jl"))
                delete!(precompiles_dict, strip(other_precompile))
            end
            if isempty(precompiles_dict)
                @info "No new precompiles to add to cache at `$cache_load_path`, skipping cache package creation for suffix `$suffix`"
                return Base.PkgId[]
            end
        end
    else
        if isempty(precompiles_dict)
            @info "No new precompiles to add to cache at `$cache_load_path`, skipping cache package creation for suffix `$suffix`"
            return Base.PkgId[]
        end
    end

    precompiles = sort!(collect(keys(precompiles_dict)), by=k->precompiles_dict[k])
    partitions = Iterators.partition(precompiles, maxsize)
    npartitions = length(partitions)
    pkgids = Vector{Base.PkgId}(undef, npartitions)
    for (i, partition) in enumerate(partitions)
        cache_pkg_name_partitioned = string(cache_pkg_name, "_", lpad(string(i), Int(ceil(log10(npartitions))), '0'))
        pkgids[i] = generate_cache_pkg(cache_load_path, cache_pkg_name_partitioned, project, partition)
    end
    return pkgids
end

function _parse_deps(io)
    project = Pkg.TOML.parse(io)
    deps = collect(project["deps"])
    push!(deps, project["name"] => project["uuid"])
    return sort!(deps)
end
function generate_cache_pkg(cache_load_path, cache_pkg_name, project, precompiles)
    deps = open(_parse_deps, project)

    mkpath(joinpath(cache_load_path, cache_pkg_name, "src"))
    local uuid
    try
        open(joinpath(cache_load_path, cache_pkg_name, "src", string(cache_pkg_name, ".jl")), "w") do io
            println(io, "module ", cache_pkg_name)
            println(io, "# Automatically generated on ", Dates.now())
            println(io, "# You shouldn't need to edit these files manually")
            println(io)
            println(io, "# Loading the dependencies of the original project that generated the `precompiles.jl` file")
            for dep in deps
                println(io, "using ", first(dep))
            end
            println(io)
            println(io, """
            # Precompile statements might use types from transitive dependencies, this
            # block makes all of those available as constants
            for (pkgid, mod) in Base.loaded_modules
                if !(pkgid.name in ("Main", "Core", "Base", $(join((repr(first(dep)) for dep in deps), ", "))))
                    Base.eval(@__MODULE__, :(const \$(Symbol(mod)) = \$mod))
                end
            end
            """)

            println(io)
            println(io, """
            function _check(expr::Expr)
                quote
                    esc(try
                        \$expr;
                    catch e;
                        @warn("Precompilation failed for `\$(\$(string(expr)))`",
                            exception=e,
                            _file=\"$(joinpath(cache_load_path, cache_pkg_name, "src", "precompiles.jl"))\",
                            _line=nothing,
                            _module=$cache_pkg_name,
                        )
                        return nothing;
                    end)
                end
            end
            """)
            println(io, "# The deduplication logic relies on this file to exist in the cache package")
            println(io, "include(_check, \"precompiles.jl\")")
            println(io)
            println(io, "end # module")
        end

        open(joinpath(cache_load_path, cache_pkg_name, "src", "precompiles.jl"), "w") do io
            for precompile in precompiles
                println(io, precompile)
            end
        end

        uuid = UUIDs.uuid4()
        open(joinpath(cache_load_path, cache_pkg_name, "Project.toml"), "w") do io
            println(io, "name = \"", cache_pkg_name, "\"")
            println(io, "uuid = \"", string(uuid), "\"")
            println(io, "authors = [\"RelationalAI\"]")
            println(io, "version = \"0.1.0\"")
            println(io)
            println(io, "[deps]")
            for (dep_name, dep_uuid) in deps
                println(io, dep_name, " = \"", string(dep_uuid), "\"")
            end
        end
    catch
        rm(joinpath(cache_load_path, cache_pkg_name), recursive=true, force=true)
        rethrow()
    end
    return Base.PkgId(uuid, cache_pkg_name)
end

_parse_pkgid(io) = (toml = Pkg.TOML.parse(io); Base.PkgId(UUID(toml["uuid"]), toml["name"]))
function precompile_all_caches(cache_load_path=CACHE_PACKAGES_LOAD_PATH[]; maxtasks=MAX_CONCURRENT_PRECOMPILES[])
    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    maxtasks < 1 && ArgumentError("`maxtasks` must be a positive integer")

    cache_paths = list_all_caches(cache_load_path, join=true)
    isempty(cache_paths) && return nothing # TODO: log

    maxtasks = min(length(cache_paths), maxtasks)
    queue = Channel{String}(Inf)
    tasks = Task[]

    for cache_pkg_path in cache_paths
        put!(queue, cache_pkg_path)
    end

    for _ in 1:maxtasks
        t = Threads.@spawn begin
            q = $queue
            while !isempty(q)
                cache_pkg_path = take!(q)
                pkgid = open(_parse_pkgid, joinpath(cache_pkg_path, "Project.toml"))
                if !Base.isprecompiled(pkgid)
                    time = @timed Base.compilecache(pkgid)
                    @info "Precompiled `$(pkgid)` in $(time.time) seconds"
                end
            end
        end
        push!(tasks, t)
    end
    try
        foreach(wait, tasks)
    catch ex
        close(queue, ex)
        @warn "Parallel precompilation failed. Compilation will be attempted at load time, serially." exception=ex
    end
    return nothing
end


function load_all_caches(
    mod=Main, cache_load_path=CACHE_PACKAGES_LOAD_PATH[];
    maxtasks=MAX_CONCURRENT_PRECOMPILES[]
)
    cache_load_path in LOAD_PATH || error("Cache directory `$cache_load_path` is not in LOAD_PATH")

    precompile_all_caches(cache_load_path; maxtasks)

    for cache_pkg_path in readdir(cache_load_path, join=true)
        _is_cache_pkg_path(cache_pkg_path) || continue
        try
            Base.require(mod, Symbol(basename(cache_pkg_path)))
        catch ex
            # TODO: the source location could be improved
            bt = catch_backtrace()
            @warn "Failed to load cache package `$(cache_pkg_path)`" exception=(ex,bt) _file=cache_pkg_path _module=cache_pkg_name _line=1
        end
    end
end

function drop_all_caches(cache_load_path=CACHE_PACKAGES_LOAD_PATH[]; force=false)
    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    version = string("v", VERSION.major, ".", VERSION.minor) # TODO: support multiple versions
    if !force
        any(f->isdir(f) && !startswith(CACHE_PACKAGE_NAME_PREFIX), readdir(cache_load_path)) &&
            error("Cache directory `$cache_load_path` contains non-cache packages, won't delete anything")
    end
    for cache_pkg_name in readdir(cache_load_path)
        cache_pkg_path = joinpath(cache_load_path, cache_pkg_name)
        cache_compiled_path = joinpath(CACHE_PACKAGES_DEPOT_PATH[], "compiled", version, cache_pkg_name)
        isdir(cache_pkg_path) && rm(cache_pkg_path, recursive=true, force=true)
        isdir(cache_compiled_path) && rm(cache_compiled_path, recursive=true, force=true)
    end
end

end # module CachePackages
