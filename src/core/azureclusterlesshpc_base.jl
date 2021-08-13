#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

# Gather parameters from parameter file
const default_parameters = [
    ["_POOL_ID", "BatchPool"],
    ["_POOL_COUNT", "1"],
    ["_NODE_COUNT_PER_POOL", "1"],
    ["_POOL_VM_SIZE", "Standard_E2s_v3"],
    ["_JOB_ID" "BatchJob"],
    ["_STANDARD_OUT_FILE_NAME", "stdout.txt"],
    ["_NODE_OS_PUBLISHER", "Canonical"],
    ["_NODE_OS_OFFER", "UbuntuServer"],
    ["_NODE_OS_SKU", "18.04"],
    ["_BLOB_CONTAINER", "azureclusterlesshpctemp"],
    ["_INTER_NODE_CONNECTION", "0"],
    ["_NUM_RETRYS", "0"],
    ["_MPI_RUN", "0"],
    ["_CONTAINER", "None"],
    ["_NUM_NODES_PER_TASK", "1"],
    ["_NUM_PROCS_PER_NODE", "1"],
    ["_OMP_NUM_THREADS", "1"],
    ["_JULIA_DEPOT_PATH", "/mnt/batch/tasks/startup/wd/.julia"],
    ["_PYTHONPATH", "/mnt/batch/tasks/startup/wd/.local/lib/python3.6/site-packages"],
    ["_VERBOSE", "1"]
]

function create_parameter_dict(params, default_parameters)

    for parameter in default_parameters
        if haskey(params, parameter[1])
            parameter[2] = params[parameter[1]]
        end
    end

    default_parameters = Dict(default_parameters)
    if default_parameters["_INTER_NODE_CONNECTION"] == "0" && parse(Int, default_parameters["_NUM_NODES_PER_TASK"]) > 1
        @warn "Cannot set _NUM_NODES_PER_TASK > 1 if _INTER_NODE_CONNECTION=0. Defaulting to _NUM_NODES_PER_TASK = 1."
        default_parameters["_NUM_NODES_PER_TASK"] = "1"
    end

    return default_parameters
end

# Manage batch state
"""
    batch_show  ()

 Print the collected expressions that have been priorly tagged via `@batchdef` and `@bcast`.

 See also: [`batch_clear`](@ref)
"""
function batch_show()
    print("__resources__: \n$__resources__\n")
    print("__expressions__: \n$__expressions__\n")
    print("__packages__: \n$__packages__\n")
end


# Clear global vars
"""
    batch_clear()

 Clear all expressions from the AzureClusterlessHPC call stack. All expressions priorly tagged with `@batchdef` or `@bcast` will be cleared.

 See also: [`batch_show`](@ref)
"""
function batch_clear()
    global __expressions__ = nothing    # collect generic expressions tagged with @batchdef
    global __packages__ = nothing   # collect "using" statements tagged with @batchdef
    if ~isnothing(__credentials__)
        global __resources__ = Array{Any}(undef, length(__credentials__))
        for i=1:length(__credentials__)
            __resources__[i] = []
        end
    else
        global __resources__ = Array{Any}(undef, 0)
    end
    if length(__active_pools__) > 0
        global __active_pools__ = Array{Dict}(undef, 0)
    end
end    


# Delete pool
"""
    delete_pool(; pool_id=nothing)

 Delete the batch pool that is specified in the parameter.json file (or delete the pool with the default name).

 *Optional input:*

 - `pool_id=nothing`: If no pool id is provided, the function deletes the pool name specified in 
    the paramter json file, or if no file is provided, the default pool (`BatchPool`).
 
 *Output*

 - `Nothing`

 See also: [`delete_all_jobs`](@ref), [`delete_container!`](@ref)
"""
function delete_pool(; pool_id=nothing)
    try
        for pool in __active_pools__
            isnothing(pool_id) ? (current_pool = pool["pool_id"]) : (current_pool = pool_id)
            pool["clients"]["batch_client"].pool.delete(current_pool)
        end
    catch
        print("Pool does not exist.")
    end
end

# Shortcuts to blob functions
"""
    delete_container(; blobcontainer=nothing)

 Delete the blob container that contains temporary blob files as specified in the parameter.json file.

 *Optional input:*

 - `blobcontainer=nothing`: Blob container name. If no name is provided, the function deletes the container specified in 
    the paramter json file, or if no file is provided, the default container (`azureclusterlesshpctemp`).
 
 *Output*

 - `Bool`

 See also: [`delete_all_jobs`](@ref), [`delete_pool!`](@ref)
"""
function delete_container(; blobcontainer=nothing)
    isnothing(blobcontainer) && (blobcontainer = __params__["_BLOB_CONTAINER"])
    for client in __clients__
        client["blob_client"].delete_container(blobcontainer)
    end
end


"""
    delete_all_jobs()

 Delete all jobs containing the current (base) job ID specified in the parameter file (or the default name).

 *Output*

 - `Nothing`

 See also: [`delete_container`](@ref), [`delete_pool!`](@ref)
"""
function delete_all_jobs(;base_id=nothing)
	isnothing(base_id) && (base_id = __params__["_JOB_ID"])
    for client in __clients__
        job_list = client["batch_client"].job.list(raw=true)
        while true
            try
                job = job_list.next()
                job_id = job.id
                if job_id[1:length(base_id)] == base_id
                    client["batch_client"].job.delete(job_id)
                end
            catch
                break
            end
        end
    end
end


"""
    Options(; job_name="batchjob_", task_name="task_", priority=0)

 Specify job options for batch jobs.

 *Input"

 - `job_name`: Name of the batch job.

 - `task_name`: Base string for task names.

 - `priority` (Int): Job priority

 *Output*

 - `Options` data structure.

"""
struct Options
    job_name::String
    job_name_full::Union{Nothing, String}
    task_name::String
    task_name_full::Union{Nothing, String}
    priority::Integer
    pool::Union{Nothing, Integer}
    reset_mpi::Bool
end

Options(; job_name="batchjob_", job_name_full=nothing, task_name="task_", task_name_full=nothing, priority=0, pool=nothing, reset_mpi=false) = Options(job_name, job_name_full, task_name, task_name_full, priority, pool, reset_mpi)

# Include generic text files (e.g. python files) with task
function fileinclude(s::String)
    return nothing
end