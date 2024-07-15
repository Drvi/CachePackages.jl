using UUIDs
using Base.CoreLogging: @logmsg
using Base: @constprop

function unsafe_require(into::Module, mod::Symbol)
    # if Base._require_world_age[] != typemax(UInt)
    #     Base.invoke_in_world(Base._require_world_age[], __unsafe_require, into, mod)
    # else
        @invokelatest __unsafe_require(into, mod)
    # end
end

function __unsafe_require(into::Module, mod::Symbol)
    @lock Base.require_lock begin
    Base.LOADING_CACHE[] = Base.LoadingCache()
    try
        uuidkey_env = Base.identify_package_env(into, String(mod))
        # Core.println("require($(Base.PkgId(into)), $mod) -> $uuidkey_env")
        if uuidkey_env === nothing
            where = Base.PkgId(into)
            if where.uuid === nothing
                hint, dots = begin
                    if isdefined(into, mod) && getfield(into, mod) isa Module
                        true, "."
                    elseif isdefined(parentmodule(into), mod) && getfield(parentmodule(into), mod) isa Module
                        true, ".."
                    else
                        false, ""
                    end
                end
                hint_message = hint ? ", maybe you meant `import/using $(dots)$(mod)`" : ""
                start_sentence = hint ? "Otherwise, run" : "Run"
                throw(ArgumentError("""
                    Package $mod not found in current path$hint_message.
                    - $start_sentence `import Pkg; Pkg.add($(repr(String(mod))))` to install the $mod package."""))
            else
                throw(ArgumentError("""
                Package $(where.name) does not have $mod in its dependencies:
                - You may have a partially installed environment. Try `Pkg.instantiate()`
                  to ensure all packages in the environment are installed.
                - Or, if you have $(where.name) checked out for development and have
                  added $mod as a dependency but haven't updated your primary
                  environment's manifest file, try `Pkg.resolve()`.
                - Otherwise you may need to report an issue with $(where.name)"""))
            end
        end
        uuidkey, env = uuidkey_env
        # if _track_dependencies[]
        #     push!(_require_dependencies, (into, binpack(uuidkey), 0.0))
        # end
        return _unsafe_require_prelocked(uuidkey, env)
    finally
        Base.LOADING_CACHE[] = nothing
    end
    end
end

unsafe_require(uuidkey::Base.PkgId) = @lock Base.require_lock _unsafe_require_prelocked(uuidkey)

const REPL_PKGID = Base.PkgId(UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL")

function _unsafe_require_prelocked(uuidkey::Base.PkgId, env=nothing)
    # if Base._require_world_age[] != typemax(UInt)
    #     Base.invoke_in_world(Base._require_world_age[], __unsafe_require_prelocked, uuidkey, env)
    # else
        @invokelatest __unsafe_require_prelocked(uuidkey, env)
    # end
end

function __unsafe_require_prelocked(uuidkey::Base.PkgId, env=nothing)
    Base.assert_havelock(Base.require_lock)
    if !Base.root_module_exists(uuidkey)
        newm = _unsafe_require(uuidkey, env)
        if newm === nothing
            error("package `$(uuidkey.name)` did not define the expected \
                  module `$(uuidkey.name)`, check for typos in package module name")
        end
        Base.insert_extension_triggers(uuidkey)
        # After successfully loading, notify downstream consumers
        Base.run_package_callbacks(uuidkey)
        if uuidkey == REPL_PKGID
            Base.REPL_MODULE_REF[] = newm
        end
    else
        m = get(Base.loaded_modules, uuidkey, nothing)
        if m !== nothing
            Base.explicit_loaded_modules[uuidkey] = m
            Base.run_package_callbacks(uuidkey)
        end
        newm = root_module(uuidkey)
    end
    return newm
end

# Returns `nothing` or the new(ish) module
function _unsafe_require(pkg::Base.PkgId, env=nothing)
    Base.assert_havelock(Base.require_lock)
    loaded = Base.start_loading(pkg)
    loaded === nothing || return loaded

    last = Base.toplevel_load[]
    try
        Base.toplevel_load[] = false
        # perform the search operation to select the module file require intends to load
        path = Base.locate_package(pkg, env)
        if path === nothing
            throw(ArgumentError("""
                Package $pkg is required but does not seem to be installed:
                 - Run `Pkg.instantiate()` to install all recorded dependencies.
                """))
        end
        Base.set_pkgorigin_version_path(pkg, path)

        pkg_precompile_attempted = false # being safe to avoid getting stuck in a Pkg.precompile loop

        # attempt to load the module file via the precompile cache locations
        if Base.JLOptions().use_compiled_modules != 0
            @label load_from_cache
            m = _unsafe_require_search_from_serialized(pkg, path, UInt128(0))
            if m isa Module
                return m
            end
        end

        # if the module being required was supposed to have a particular version
        # but it was not handled by the precompile loader, complain
        for (concrete_pkg, concrete_build_id) in Base._concrete_dependencies
            if pkg == concrete_pkg
                @warn """Module $(pkg.name) with build ID $((UUID(concrete_build_id))) is missing from the cache.
                     This may mean $pkg does not support precompilation but is imported by a module that does."""
                if Base.JLOptions().incremental != 0
                    # during incremental precompilation, this should be fail-fast
                    throw(Base.PrecompilableError())
                end
            end
        end

        if Base.JLOptions().use_compiled_modules != 0
            if (0 == ccall(:jl_generating_output, Cint, ())) || (Base.JLOptions().incremental != 0)
                if !pkg_precompile_attempted && isinteractive() && isassigned(Base.PKG_PRECOMPILE_HOOK)
                    pkg_precompile_attempted = true
                    unlock(Base.require_lock)
                    try
                        @invokelatest Base.PKG_PRECOMPILE_HOOK[](pkg.name, _from_loading = true)
                    finally
                        lock(Base.require_lock)
                    end
                    @goto load_from_cache
                end
                # spawn off a new incremental pre-compile task for recursive `require` calls
                cachefile_or_module = Base.maybe_cachefile_lock(pkg, path) do
                    # double-check now that we have lock
                    m = _unsafe_require_search_from_serialized(pkg, path, UInt128(0))
                    m isa Module && return m
                    Base.compilecache(pkg, path)
                end
                cachefile_or_module isa Module && return cachefile_or_module::Module
                cachefile = cachefile_or_module
                if isnothing(cachefile) # maybe_cachefile_lock returns nothing if it had to wait for another process
                    @goto load_from_cache # the new cachefile will have the newest mtime so will come first in the search
                elseif isa(cachefile, Exception)
                    if precompilableerror(cachefile)
                        verbosity = isinteractive() ? CoreLogging.Info : CoreLogging.Debug
                        @logmsg verbosity "Skipping precompilation since __precompile__(false). Importing $pkg."
                    else
                        @warn "The call to compilecache failed to create a usable precompiled cache file for $pkg" exception=m
                    end
                    # fall-through to loading the file locally if not incremental
                else
                    cachefile, ocachefile = cachefile::Tuple{String, Union{Nothing, String}}
                    m = _unsafe_tryrequire_from_serialized(pkg, cachefile, ocachefile)
                    if !isa(m, Module)
                        @warn "The call to compilecache failed to create a usable precompiled cache file for $pkg" exception=m
                    else
                        return m
                    end
                end
                if Base.JLOptions().incremental != 0
                    # during incremental precompilation, this should be fail-fast
                    throw(PrecompilableError())
                end
            end
        end

        # just load the file normally via include
        # for unknown dependencies
        uuid = pkg.uuid
        uuid = (uuid === nothing ? (UInt64(0), UInt64(0)) : convert(NTuple{2, UInt64}, uuid))
        old_uuid = ccall(:jl_module_uuid, NTuple{2, UInt64}, (Any,), __toplevel__)
        if uuid !== old_uuid
            ccall(:jl_set_module_uuid, Cvoid, (Any, NTuple{2, UInt64}), __toplevel__, uuid)
        end
        unlock(Base.require_lock)
        try
            include(__toplevel__, path)
            loaded = get(loaded_modules, pkg, nothing)
        finally
            lock(Base.require_lock)
            if uuid !== old_uuid
                ccall(:jl_set_module_uuid, Cvoid, (Any, NTuple{2, UInt64}), __toplevel__, old_uuid)
            end
        end
    finally
        Base.toplevel_load[] = last
        Base.end_loading(pkg, loaded)
    end
    return loaded
end

# loads a precompile cache file, ignoring stale_cachefile tests
# load the best available (non-stale) version of all dependent modules first
function _unsafe_tryrequire_from_serialized(pkg::Base.PkgId, path::String, ocachepath::Union{Nothing, String})
    Base.assert_havelock(Base.require_lock)
    local depmodnames
    io = open(path, "r")
    try
        iszero(Base.isvalid_cache_header(io)) && return ArgumentError("Invalid header in cache file $path.")
        _, _, depmodnames, _, _, _, clone_targets, _ = Base.parse_cache_header(io)
        pkgimage = !isempty(clone_targets)
        if pkgimage
            ocachepath !== nothing || return ArgumentError("Expected ocachepath to be provided")
            isfile(ocachepath) || return ArgumentError("Ocachepath $ocachepath is not a file.")
            ocachepath == Base.ocachefile_from_cachefile(path) || return ArgumentError("$ocachepath is not the expected ocachefile")
            # TODO: Check for valid clone_targets?
            Base.isvalid_pkgimage_crc(io, ocachepath) || return ArgumentError("Invalid checksum in cache file $ocachepath.")
        else
            @assert ocachepath === nothing
        end
        Base.isvalid_file_crc(io) || return ArgumentError("Invalid checksum in cache file $path.")
    finally
        close(io)
    end
    ndeps = length(depmodnames)
    depmods = Vector{Any}(undef, ndeps)
    for i in 1:ndeps
        modkey, build_id = depmodnames[i]
        dep = _unsafe_tryrequire_from_serialized(modkey, build_id)
        if !isa(dep, Module)
            return dep
        end
        depmods[i] = dep
    end
    # then load the file
    return Base._include_from_serialized(pkg, path, ocachepath, depmods, #=cheat=#1)
end

function _unsafe_tryrequire_from_serialized(modkey::Base.PkgId, path::String, ocachepath::Union{Nothing, String}, sourcepath::String, depmods::Vector{Any})
    Base.assert_havelock(Base.require_lock)
    loaded = nothing
    if Base.root_module_exists(modkey)
        loaded = Base.root_module(modkey)
    else
        loaded = Base.start_loading(modkey)
        if loaded === nothing
            try
                for i in 1:length(depmods)
                    dep = depmods[i]
                    dep isa Module && continue
                    _, depkey, depbuild_id = dep::Tuple{String, Base.PkgId, UInt128}
                    @assert Base.root_module_exists(depkey)
                    dep = Base.root_module(depkey)
                    depmods[i] = dep
                end
                Base.set_pkgorigin_version_path(modkey, sourcepath)
                loaded = Base._include_from_serialized(modkey, path, ocachepath, depmods, #=cheat=#1)
            finally
                Base.end_loading(modkey, loaded)
            end
            if loaded isa Module
                Base.insert_extension_triggers(modkey)
                Base.run_package_callbacks(modkey)
            end
        end
    end
    if !(loaded isa Module) || Base.PkgId(loaded) != modkey
        return ErrorException("Required dependency $modkey failed to load from a cache file.")
    end
    return loaded
end

# loads a precompile cache file, after checking stale_cachefile tests
function _unsafe_tryrequire_from_serialized(modkey::Base.PkgId, build_id::UInt128)
    Base.assert_havelock(Base.require_lock)
    loaded = nothing
    if root_module_exists(modkey)
        loaded = Base.root_module(modkey)
    else
        loaded = Base.start_loading(modkey)
        if loaded === nothing
            try
                modpath = Base.locate_package(modkey)
                modpath === nothing && return nothing
                Base.set_pkgorigin_version_path(modkey, String(modpath))
                loaded = _unsafe_require_search_from_serialized(modkey, String(modpath), build_id)
            finally
                Base.end_loading(modkey, loaded)
            end
            if loaded isa Module
                Base.insert_extension_triggers(modkey)
                Base.run_package_callbacks(modkey)
            end
        end
    end
    if !(loaded isa Module) || Base.PkgId(loaded) != modkey
        return ErrorException("Required dependency $modkey failed to load from a cache file.")
    end
    return loaded
end


# returns `nothing` if require found a precompile cache for this sourcepath, but couldn't load it
# returns the set of modules restored if the cache load succeeded
@constprop :none function _unsafe_require_search_from_serialized(pkg::Base.PkgId, sourcepath::String, build_id::UInt128)
    Base.assert_havelock(Base.require_lock)
    paths = Base.find_all_in_cache_path(pkg)
    for path_to_try in paths::Vector{String}
        staledeps = Base.stale_cachefile(pkg, build_id, sourcepath, path_to_try)
        if staledeps === true
            continue
        end
        staledeps, ocachefile = staledeps::Tuple{Vector{Any}, Union{Nothing, String}}
        # finish checking staledeps module graph
        for i in 1:length(staledeps)
            dep = staledeps[i]
            dep isa Module && continue
            modpath, modkey, modbuild_id = dep::Tuple{String, Base.PkgId, UInt128}
            modpaths = Base.find_all_in_cache_path(modkey)
            for modpath_to_try in modpaths
                modstaledeps = Base.stale_cachefile(modkey, modbuild_id, modpath, modpath_to_try)
                if modstaledeps === true
                    continue
                end
                modstaledeps, modocachepath = modstaledeps::Tuple{Vector{Any}, Union{Nothing, String}}
                staledeps[i] = (modpath, modkey, modpath_to_try, modstaledeps, modocachepath)
                @goto check_next_dep
            end
            @debug "Rejecting cache file $path_to_try because required dependency $modkey with build ID $(UUID(modbuild_id)) is missing from the cache."
            @goto check_next_path
            @label check_next_dep
        end
        try
            touch(path_to_try) # update timestamp of precompilation file
        catch ex # file might be read-only and then we fail to update timestamp, which is fine
            ex isa IOError || rethrow()
        end
        # finish loading module graph into staledeps
        for i in 1:length(staledeps)
            dep = staledeps[i]
            dep isa Module && continue
            modpath, modkey, modcachepath, modstaledeps, modocachepath = dep::Tuple{String, Base.PkgId, String, Vector{Any}, Union{Nothing, String}}
            dep = _unsafe_tryrequire_from_serialized(modkey, modcachepath, modocachepath, modpath, modstaledeps)
            if !isa(dep, Module)
                @debug "Rejecting cache file $path_to_try because required dependency $modkey failed to load from cache file for $modcachepath." exception=dep
                @goto check_next_path
            end
            staledeps[i] = dep
        end
        restored = Base._include_from_serialized(pkg, path_to_try, ocachefile, staledeps, #=cheat=#1)
        isa(restored, Module) && return restored
        @debug "Deserialization checks failed while attempting to load cache from $path_to_try" exception=restored
        continue
        @label check_next_path
    end
    return nothing
end
