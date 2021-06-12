#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

export BatchController, terminate_job, delete_job, delete_pool, resize_pool, wait_for_tasks_to_complete, fetch, destroy!
export fetchreduce,  fetchreduce!, get_job_stats



"""
    bctrl = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, clients)

 Batch controller that provides access to return arguments of batch jobs, as well as basic job and 
 pool functionalities. Used as a return argument for batch macro @batchexec.

 *Input*:

 - `pool_id` (Array{String}): List of batch pools in which jobs were executed.

 - `job_id` (Array{String}): Job ID for which batch controller is returned

 - `task_id` (Array{Dict, 1}): List of task names of the respective batch job and the corresponding pool no.

 - `num_tasks` (Integer): Number of tasks in batch job

 - `output` (Array{Any, 1}): List of outputs, one cell entry per task. The list contains one blob future for each task

 - `blobcontainer` (String): Name of Blob container in which (temporary) results are stored

 - `clients` (Dict): Dictionary with entries `batch_client` and `blob_client`, each of which are a PyObject of clients


 *Output*:

 - `bctrl`: Batch control structure


 *Usage*:

 - Terminate batch job: `terminate_job(bctrl)`

 - Delete batch job: `delete_job(bctrl)`

 - Delete batch pool: `delete_pool(bctrl)`

 - Delete blob container: `delete_container(bctrl)`

 - Delete pool, job and container: `destroy!(bctrl)`
 
 - Resize pool: `resize_pool(bctrl; target_dedicated_nodes=0, target_low_priority_nodes=0)`

 - Wait for all tasks to complete: `wait_for_task_to_complete(bctrl)`

 - Fetch output (i.e. return arguments of executed function): `fetch(bctrl; destroy_blob=false, timeout=60)`

 - Fetch output of task `i`: `fetch(bctrl, i; destroy_blob=false, timeout=60)`

 - Inplace fetch (overwrite blob futures in `bctrl.output`): `fetch!(bctrl; destroy_blob=true, timeout=60)`

-  Inplace fetch for task `i`: `fetch!(bctrl, i; destroy_blob=true, timeout=60)`

- Fetch output and apply reduce function to it: `fetchreduce(bctrl; op=+, remote=false, destroy_blob=false, timeout=60)`

- Inplace fetch and reduction operation: `fetchreduce!(bctrl, output; op=+, destroy_blob=false, timeout=60)`

 See also: [`@batchdef`](@ref), [`@batchexec`](@ref) 
"""
mutable struct BatchController
    pool_id::Union{String, Array}
    job_id::Union{Array, String}
    task_id::Array{Dict, 1}
    num_tasks::Integer
    output::Array{Any, 1}
    blobcontainer::String
    batch_client::Union{Array, Nothing}
    blob_client::Union{Array, Nothing}
end

function BatchController(job_id, task_id, num_tasks, output)

    batch_clients = []
    blob_clients = []
    pool_id = []
    for pool in __active_pools__
        push!(batch_clients, pool["clients"]["batch_client"])
        push!(blob_clients, pool["clients"]["blob_client"])
        push!(pool_id, pool["pool_id"])
    end
    blobcontainer = __container__

    return BatchController(
        pool_id,
        job_id,
        task_id,
        num_tasks,
        output,
        blobcontainer,
        batch_clients,
        blob_clients
    )
end

###################################################################################################
# Methods

# Shortcuts to job functions
"""
    terminate_job(batch_controller::BatchController)

 Terminate the batch job of the provided batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Nothing
 
"""
function terminate_job(batch_controller::BatchController)
    for (i, batch_client) in enumerate(batch_controller.batch_client)
        batch_client.job.terminate(batch_controller.job_id[i])
    end
end


"""
    delete_job(batch_controller::BatchController)

 Delete the batch job of the provided batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Nothing
 
"""
function delete_job(batch_controller::BatchController)
    for (i, batch_client) in enumerate(batch_controller.batch_client)
        batch_client.job.delete(batch_controller.job_id[i])
    end
end


# Shortcuts to pool functions
"""
    delete_pool(batch_controller::BatchController)

 Delete the pool of the provided batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Nothing
 
"""
function delete_pool(batch_controller::BatchController)
    for (pool_id, batch_client) in zip(batch_controller.pool_id, batch_controller.batch_client)
        batch_client.pool.delete(pool_id)
    end
end


# Shortcuts to blob functions
"""
    delete_container(batch_controller::BatchController)

 Delete the blob container of the provided batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Bool
 
"""
function delete_container(batch_controller::BatchController)
    for client in __clients__
        client["blob_client"].delete_container(batch_controller.blobcontainer)
    end
end


"""
    resize_pool(batch_controller::BatchController)

 Resize the batch pool of the provided batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 - `target_dedicated_nodes` (Integer): New number of dedicated nodes

 - `target_low_priority_nodes` (Integer): New number of spot nodes

 *Output*:

 - Nothing
 
"""
function resize_pool(batch_controller::BatchController; target_dedicated_nodes=nothing, target_low_priority_nodes=nothing)
    pool_resize = batchmodels.PoolResizeParameter(target_dedicated_nodes=target_dedicated_nodes, 
        target_low_priority_nodes=target_low_priority_nodes)
    for (pool_id, batch_client) in zip(batch_controller.pool_id, batch_controller.batch_client)
        batch_client.pool.resize(pool_id, pool_resize)
    end
end

# Wait for jobs to finish
"""
    wait_for_tasks_to_complete(batch_controller::BatchController)

 Wait for all tasks of the batch job to complete.

 *Input*:

 - `batch_controller`: Batch control structure

 - `timeout`: Maximum runtime per task in minutes (default is `60`).

 - `num_restart`: Allowed retries for failed tasks (default is `0`).

 *Output*:

 - Nothing
 
"""
function wait_for_tasks_to_complete(batch_controller::BatchController; timeout=60, num_restart=0)
    status = []
    @sync begin
        for (i, batch_client) in enumerate(batch_controller.batch_client)
            @async push!(status, wait_for_tasks_to_complete(batch_client, batch_controller.job_id[i], timeout; 
                verbose=__verbose__, num_restart=num_restart))
        end
    end

    # Return indices of failed tasks
    return status[findall(i -> typeof(i) != Bool, status)]
end

# Get job information
"""
    get_job_stats(batch_controller::BatchController)

 Get runtime information about the job and its associated tasks.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Dictionary with statistics.
 
"""
function get_job_stats(bctrl::BatchController)

    # Job information
    job_id = bctrl.job_id
    num_pools = length(bctrl.batch_client)

    job_creation_time = Array{Any}(undef, num_pools)
    job_start_time = Array{Any}(undef, num_pools)
    job_end_time = Array{Any}(undef, num_pools)
    job_state_transition_time = Array{Any}(undef, num_pools)

    task_creation_time = []
    task_start_time = []
    task_end_time = []
    task_state_transition_time = []

    for (i, batch_client) in enumerate(bctrl.batch_client)
        job_creation_time[i] = batch_client.job.get(job_id[i]).creation_time
        job_start_time[i] = batch_client.job.list().next().execution_info.start_time
        job_end_time[i] = batch_client.job.list().next().execution_info.end_time
        job_state_transition_time[i] = batch_client.job.get(job_id[i]).state_transition_time

        for task in bctrl.task_id
            task["pool"] == i && push!(task_creation_time, batch_client.task.get(job_id[i], task["taskname"]).creation_time)
            task["pool"] == i && push!(task_start_time, batch_client.task.get(job_id[i], task["taskname"]).execution_info.start_time)
            task["pool"] == i && push!(task_end_time, batch_client.task.get(job_id[i], task["taskname"]).execution_info.end_time)
            task["pool"] == i && push!(task_state_transition_time, batch_client.task.get(job_id[i], task["taskname"]).state_transition_time)
        end
    end

    return Dict("job_id" => job_id,
        "job_creation_time" => job_creation_time,
        "job_start_time" => job_start_time,
        "job_end_time" => job_end_time,
        "job_state_transition_time" => job_state_transition_time,

        "task_ids" => bctrl.task_id,
        "task_creation_time" => task_creation_time,
        "task_start_time" => task_start_time,
        "task_end_time" => task_end_time,
        "task_state_transition_time" => task_state_transition_time
    )
end
    

"""
destroy!(batch_controller::BatchController)

 Delete the pool, container and job of the batch controller.

 *Input*:

 - `batch_controller`: Batch control structure

 *Output*:

 - Nothing
 
"""
function destroy!(batch_controller::BatchController)
    # Clean up resources
    try
        terminate_job(batch_controller) 
    catch
        nothing
    end
    try
        delete_job(batch_controller)
    catch
        nothing
    end
    try
        delete_pool(batch_controller)
    catch
        nothing
    end
    try
        delete_container(batch_controller)
    catch
        nothing
    end
    return true
end