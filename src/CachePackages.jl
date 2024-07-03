module CachePackages

using Pkg, TOML, UUIDs, Dates

const CACHE_PACKAGES_PATH = Ref{String}()
const CACHE_PACKAGES_PATH_LOCK = ReentrantLock()
function __init__()
    global CACHE_PACKAGES_PATH[] = tempdir()
end

export set_cache_package_path_and_add_it_to_load_path!, make_pkgimage_cache, load_all_caches, drop_all_caches

function set_cache_package_path_and_add_it_to_load_path!(path)
    @lock CACHE_PACKAGES_PATH_LOCK begin
        CACHE_PACKAGES_PATH[] = path
        path in LOAD_PATH || push!(LOAD_PATH, path) # Split this into two methods?
    end
end

_now() = Dates.format(Dates.now(), "yyyymmddHHMMSSsss")

function make_pkgimage_cache(precompiles_path, suffix=_now(); dedupe=true, project=Base.active_project(), cache_load_path=CACHE_PACKAGES_PATH[])
    cache_pkg_name = string("Cache", string(suffix))

    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    isfile(precompiles_path) || error("Precompiles file cannot be found at path `$precompiles_path`")
    !isdir(joinpath(cache_load_path, cache_pkg_name)) || error("Cache with suffix `$suffix` already exists at `$(joinpath(cache_load_path, cache_pkg_name))`")

    precompiles = Set(eachline(precompiles_path)) # TODO: preserve order

    if dedupe
        for other_cache_pkg_name in readdir(cache_load_path, join=true)
            isdir(other_cache_pkg_name) || continue
            startswith("Cache", basename(other_cache_pkg_name)) || continue
            for other_precompile in eachline(joinpath(other_cache_pkg_name, "src", "precompiles.jl"))
                delete!(precompiles, other_precompile)
            end
        end
    end

    if isempty(precompiles)
        @info "No new precompiles to add to cache at `$cache_load_path`, skipping cache package creation for suffix `$suffix`"
        return
    end

    generate_cache_pkg(cache_load_path, cache_pkg_name, project, precompiles)
end

function generate_cache_pkg(cache_load_path, cache_pkg_name, project, precompiles)
    deps = open(io->sort!(collect(Pkg.TOML.parse(io)["deps"])), project)

    mkpath(joinpath(cache_load_path, cache_pkg_name, "src"))
    try
        open(joinpath(cache_load_path, cache_pkg_name, "src", string(cache_pkg_name, ".jl")), "w") do io
            println(io, "module ", cache_pkg_name)
            println(io, "# Automatically generated at ", Dates.now())
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
                        @debug "Precompilation failed for `\$(\$(string(expr)))`" exception=e _file=\"$(joinpath(cache_load_path, cache_pkg_name))\" _line=nothing _module=$cache_pkg_name;
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
        rm(joinpath(cache_load_path, cache_pkg_name), recursive=true)
        rethrow()
    end
end

function load_all_caches(mod, cache_load_path=CACHE_PACKAGES_PATH[])
    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    cache_load_path in LOAD_PATH || error("Cache directory `$cache_load_path` is not in LOAD_PATH")

    # TODO: precompile cache packages in parallel
    # mod = Module()
    for cache_pkg_name in readdir(cache_load_path)
        if isdir(joinpath(cache_load_path, cache_pkg_name))
            try
                Base.require(mod, Symbol(cache_pkg_name))
            catch ex
                # TODO: the source location could be improved
                bt = catch_backtrace()
                @warn "Failed to load cache package `$(cache_pkg_name)`" exception=(ex,bt) _file=joinpath(cache_load_path, cache_pkg_name) _module=cache_pkg_name _line=1
            end
        end
    end
end

function drop_all_caches(cache_load_path=CACHE_PACKAGES_PATH[]; force=false)
    isdir(cache_load_path) || error("Cache directory `$cache_load_path` does not exist")
    if !force
        any(f->isdir(f) && !startswith("Cache"), readdir(cache_load_path)) && error("Cache directory `$cache_load_path` contains non-cache packages, won't delete anything")
    end
    for cache_pkg_path in readdir(cache_load_path, join=true)
        isdir(cache_pkg_path) && rm(cache_pkg_path, recursive=true, force=true)
    end
end

end # module CachePackages
