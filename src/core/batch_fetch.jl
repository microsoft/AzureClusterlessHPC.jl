#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

###################################################################################################
# Fetch methods

# Fetch output blobs for given task index (blocking)
"""
    output = fetch(object::Union{BatchController, BlobFuture, BatchFuture}; destroy_blob=false, timeout=60, task_timeout=60)

 Fetch the output from the batch job or future (i.e. the return arguments of the executed function).

    output = fetch(batch_controller::BatchController, idx; destroy_blob=false, timeout=60, wait_for_completion=true)

 Fetch the output of task `idx` only (only supported for inputs of type `BatchController`).

 *Input*:

 - `object` (BatchController, BlobFuture or BatchFuture): Batch control structure or future whose reference will be fetched. 

 - `idx` (Integer): Task number

 - `destroy_blob` (Bool): Remove the original blob upon successful fetching (default is `false`)

 - `timeout`: Maximum time to wait for all tasks to finish (in minutes). Default is `60`.

 - `task_timeout`: Maximum runtime per task (in minutes). Default is `60`.

 - `num_restart`: Allowed retries for failed tasks (default is `0`).


 *Output*:

 - `output`: List of return arguments of executed function (one entry per task) or data from blob/batch future.
 
"""
function fetch(batch_controller::BatchController, idx; destroy_blob=false, timeout=60, wait_for_completion=true, num_restart=0)

    # Wait for specified task to finish
    task_id = batch_controller.task_id[idx]["taskname"]
    pool_no = batch_controller.task_id[idx]["pool"]
    if wait_for_completion
        wait_for_task_to_complete(batch_controller.batch_client[pool_no], batch_controller.job_id[pool_no], task_id, timeout; 
            verbose=__verbose__, num_restart=num_restart)
    end

    # Loop over entries in Future for i-th task
    num_files = length(batch_controller.output[idx].blob.name)
    out_files = []
    for blob in batch_controller.output[idx].blob.name

        # Fetch blob and add to collection
        if ~isnothing(batch_controller.blob_client[pool_no])
            try
                val = batch_controller.blob_client[pool_no].get_blob_to_bytes(batch_controller.blobcontainer, blob)
                push!(out_files, deserialize(IOBuffer(val.content)))

                # Delete blob (default is true)
                destroy_blob && batch_controller.blob_client[pool_no].delete_blob(batch_controller.blobcontainer, blob)
            catch
                @warn "Blob does not exist or task has not finished yet. Return nothing."
                push!(out_files, nothing)
            end
        end
    end

    # Replace blob name in Future with value
    if num_files > 1
        return tuple(out_files...)
    elseif length(out_files) == 1
        return out_files[1]
    else
        return nothing
    end
end


"""
    data = fetch!(object::Union{BatchController, BlobFuture, BatchFuture}; destroy_blob=true, timeout=60, task_timeout=60)

 Fetch the output from the batch job or future in place (return output arguments of executed function and overwrite blob future).

    data = fetch!(batch_controller::BatchController, idx; destroy_blob=false, timeout=60, wait_for_completion=true)

 Inplace fetch of the output of task `idx` only (only supported for inputs of type `BatchController`).

 *Input*:

 - `object` (BatchController, BlobFuture or BatchFuture): Batch control structure or future whose reference will be fetched. 

 - `idx` (Integer): Task number

 - `destroy_blob` (Bool): Remove the original blob upon successful fetching (default is `true` for inplace fetch)

 - `timeout`: Maximum time to wait for all tasks to finish (in minutes). Default is `60`.

 - `task_timeout`: Maximum runtime per task (in minutes). Default is `60`.

 - `num_restart`: Allowed retries for failed tasks (default is `0`).


 *Output*:

 - `output`: List of return arguments of executed function (one entry per task) or data from blob/batch future.
 
"""
function fetch!(batch_controller::BatchController, idx; destroy_blob=true, timeout=60, wait_for_completion=true, num_restart=0)

    # Wait for specified task to finish
    task_id = batch_controller.task_id[idx]["taskname"]
    pool_no = batch_controller.task_id[idx]["pool"]
    if wait_for_completion
        wait_for_task_to_complete(batch_controller.batch_client[pool_no], batch_controller.job_id[pool_no], task_id, timeout;
            verbose=__verbose__, num_restart=num_restart)
    end

    # Loop over entries in Future for i-th task
    num_files = length(batch_controller.output[idx].blob.name)
    out_files = []
    for blob in batch_controller.output[idx].blob.name

        # Fetch blob and add to collection
        if ~isnothing(batch_controller.blob_client[pool_no])
            try
                val = batch_controller.blob_client[pool_no].get_blob_to_bytes(batch_controller.blobcontainer, blob)
                push!(out_files, deserialize(IOBuffer(val.content)))

                # Delete blob (default is true)
                destroy_blob && batch_controller.blob_client[pool_no].delete_blob(batch_controller.blobcontainer, blob)
            catch
                @warn "Blob does not exist or task has not finished yet. Return nothing."
                push!(out_files, nothing)
            end
        end
    end

    # Replace blob name in Future with value
    if num_files > 1 && length(out_files) > 1
        batch_controller.output[idx].blob = tuple(out_files...)
    elseif length(out_files) == 1
        batch_controller.output[idx].blob = out_files[1]
    else
        batch_controller.output[idx].blob = nothing
    end

    # Return value
    return batch_controller.output[idx].blob
end


# Fetch output blobs of all tasks in order of completion (blocking operation)
function fetch(batch_controller::BatchController; destroy_blob=false, timeout=60, task_timeout=60, num_restart=0)

    out_files = Array{Any}(undef, length(batch_controller.output))
    remaining_tasks = deepcopy(batch_controller.task_id)
    task_id = nothing
    __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
    while true

        # Wait for one task from task list to finish
        try
            task_id = wait_for_one_task_from_multi_pool(batch_controller.batch_client, batch_controller.job_id, remaining_tasks; 
                task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
        catch
           throw("Reached timeout for task completion.")
        end
        __verbose__ && print("\nFetch output from task $task_id")

        # Fetch its output
        task_no = findall(i -> i["taskname"] == task_id, batch_controller.task_id)[1]
        if ~isempty(remaining_tasks)
            out_files[task_no] = fetch(batch_controller, task_no; destroy_blob=destroy_blob, timeout=task_timeout, wait_for_completion=false, 
                num_restart=0)
            local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]
            popat!(remaining_tasks, local_id)
        end

        # Return it task list is empty
        if isempty(remaining_tasks)
            __verbose__ && print("\n")
            if length(out_files) > 1
                return out_files
            elseif length(out_files) == 1
                return out_files[1]
            else
                return nothing
            end
        end
    end
end


function fetch!(batch_controller::BatchController; destroy_blob=true, timeout=60, task_timeout=60, num_restart=0)

    out_files = Array{Any}(undef, length(batch_controller.output))
    remaining_tasks = deepcopy(batch_controller.task_id)
    task_id = nothing
    __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
    while true

        # Wait for one task from task list to finish
        try
            task_id = wait_for_one_task_from_multi_pool(batch_controller.batch_client, batch_controller.job_id, remaining_tasks; 
                task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
        catch
           throw("Reached timeout for task completion.")
        end
        __verbose__ && print("\nFetch output from task $task_id")

        # Fetch its output
        task_no = findall(i -> i["taskname"] == task_id, batch_controller.task_id)[1]
        if ~isempty(remaining_tasks)
            out_files[task_no] = fetch!(batch_controller, task_no; destroy_blob=destroy_blob, timeout=timeout, wait_for_completion=false)
            local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]
            popat!(remaining_tasks, local_id)
        end

        # Return it task list is empty
        if isempty(remaining_tasks)
            __verbose__ && print("\n")
            if length(out_files) > 1
                return out_files
            else
                return out_files[1]
            end
        end
    end
end


# Reduction code for remote execution
reduction_code = quote
    @batchdef function remote_reduction(_x, _y; op=+)
        x = fetch(_x)
        y = fetch(_y)
        output = broadcast(op, x, y)
        return output
    end
end

function check_for_reduction_code_in_ast(expr, count)

    # Reached AST leaf
    typeof(expr) != Expr && return

    if expr.head == :call && expr.args[1] == :remote_reduction
        count[1] += 1
    else
        # Step through AST
        for i=1:length(expr.args)
            if typeof(expr.args[i]) == Expr
                check_for_reduction_code_in_ast(expr.args[i], count)
            end
        end
    end
end

"""
    output = fetchreduce(batch_controller::BatchController; op=+, destroy_blob=false, timeout=60, remote=false)

 Fetch the output from the batch job and apply the specified reduction operation to it (across tasks).


 *Input*:

 - `batch_controller` (BatchController): Batch control structure

 - `op`: Algebraic operation to apply to the output from different tasks.

 - `destroy_blob` (Bool): Remove the original blob upon successful fetching (default is `false`)

 - `timeout`: Timeout in minutes.

 - `num_restart`: Allowed retries for failed tasks (default is `0`).

 - `remote` (Bool): If `true`, execute the reduction operation as additional batch tasks. Otherwise, the reduction happens locally.

 *Output*:

 - `output`: Return argument(s) of executed function after application of reduction operation (along tasks)
 
"""
function fetchreduce(batch_controller::BatchController; op=+, destroy_blob=false, timeout=60, task_timeout=60, 
    remote=false, reduction_code=reduction_code, num_restart=0)
    
    if remote == false
        return fetchreduce_local(batch_controller; op=op, destroy_blob=destroy_blob, timeout=timeout, 
            task_timeout=task_timeout, num_restart=num_restart)
    else
        if batch_controller.num_tasks == 1
            return fetch(batch_controller; destroy_blob=destroy_blob, timeout=timeout)
        else
            num_pools = length(batch_controller.batch_client)
            job_ids = Array{Any}(undef, num_pools)
            task_ids = Array{Any}(undef, num_pools)
            output = Array{Any}(undef, num_pools)
            orig_blobs = Array{Any}(undef, num_pools)
            temp_blobs = Array{Any}(undef, num_pools)

            count_code = [0]
            check_for_reduction_code_in_ast(__expressions__, count_code)
            count_code[1] == 0 && eval(reduction_code)
            
            # First, reduce all outputs within each storage account
            @sync begin
                for i=1:num_pools
                    @async job_ids[i], task_ids[i], output[i], orig_blobs[i], temp_blobs[i] = 
                        fetchreduce_remote(
                            batch_controller.batch_client[i],
                            batch_controller.blob_client[i],
                            batch_controller.job_id[i],
                            batch_controller.task_id[findall(k -> k["pool"] == i, batch_controller.task_id)],
                            batch_controller.output[findall(k -> k.client_index == i, batch_controller.output)],
                            batch_controller.blobcontainer,
                            i;
                            op=op, destroy_blob=destroy_blob, timeout=timeout, task_timeout=task_timeout, 
                            num_restart=num_restart)
                end
            end
            
            # Batch controller for remaining tasks (1 per storage account)
            reduce_ctrl = BatchController(job_ids, task_ids, num_pools, output)
            output = fetchreduce_local(reduce_ctrl; op=op, destroy_blob=true, timeout=timeout, task_timeout=task_timeout, 
                num_restart=num_restart)

            # Clean up
            for i=1:num_pools
                job_ids[i] != batch_controller.job_id[i] && (batch_controller.batch_client[i].job.delete(job_ids[i]))
                # Output blobs
                if destroy_blob
                    for orig_file in orig_blobs[i]
                        batch_controller.blob_client[i].delete_blob(batch_controller.blobcontainer, orig_file)
                    end
                end
                # Temp blobs
                for temp_file in temp_blobs[i]
                    batch_controller.blob_client[i].delete_blob(batch_controller.blobcontainer, temp_file)
                end
            end
            return output
        end
    end
end

# Fetch and reduce operation locally
function fetchreduce_local(batch_controller::BatchController; op=+, destroy_blob=false, timeout=60, task_timeout=60, num_restart=0)

    # Single task: simply fetch output
    if batch_controller.num_tasks == 1
        output = fetch(batch_controller)

    # Multiple tasks: fetch and sum output
    else
        remaining_tasks = deepcopy(batch_controller.task_id)
        task_id = nothing
        output = nothing

        __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
        while true

            # Wait for one task from task list to finish
            try
                task_id = wait_for_one_task_from_multi_pool(batch_controller.batch_client, batch_controller.job_id, remaining_tasks;
                    task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
            catch
                throw("Reached timeout for task completion.")
            end
            __verbose__ && print("\nFetch output from task $task_id")

            # Fetch its output
            task_no = findall(i -> i["taskname"] == task_id, batch_controller.task_id)[1]
            if ~isempty(remaining_tasks)

                # Fetch output
                if isnothing(output)
                    output = fetch(batch_controller, task_no; destroy_blob=destroy_blob, timeout=timeout, wait_for_completion=false)
                else
                    output = broadcast(op, output, fetch(batch_controller, task_no; destroy_blob=destroy_blob, 
                        timeout=timeout, wait_for_completion=false))
                end
                
                # Remove task from task list
                local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]
                popat!(remaining_tasks, local_id)
            end

            # Return it task list is empty
            if isempty(remaining_tasks)
                __verbose__ && print("\n")
                if length(output) > 1
                    return output
                elseif length(output) == 1
                    return output[1]
                else
                    return nothing
                end
            end
        end
    end
end


function wait_for_task_from_job_list!(batch_client, output, job_ids, remaining_tasks, timeout, task_timeout, 
    temp_blobs, orig_blobs, original_job_id; num_restart=0)

    # Wait for task to finish
    task_id = wait_for_one_task_from_multi_jobs(batch_client, job_ids, remaining_tasks;
    task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
    local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]

    # Remove completed task from task/job/output list
    popat!(remaining_tasks, local_id)
    completed_job_id = popat!(job_ids, local_id)
    output_ref = popat!(output, local_id)

    # Keep track of temporary blobs
    if completed_job_id != original_job_id
        push!(temp_blobs, output_ref.blob.name[1])
        batch_client.job.delete(completed_job_id)
    else
        push!(orig_blobs, output_ref.blob.name[1])
    end
    return output_ref
end


# Execute reduce function remotely
function fetchreduce_remote(batch_client, blob_client, job_id, task_id, func_output, blobcontainer, pool_no;
    op=+, destroy_blob=false, timeout=60, task_timeout=60, num_restart=0)

    # Single task: simply fetch output
    num_tasks = length(func_output)
    if num_tasks == 1
        return job_id, task_id[1], func_output[1], [], []
    else
        output = deepcopy(func_output)
        remaining_tasks = deepcopy(task_id)
        original_job_id = job_id
        job_ids = Array{Any}(undef, length(remaining_tasks)) .= job_id
        temp_blobs = []; orig_blobs = []

        __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
        while true

            # Wait for two tasks to finish
            output_ref1 = wait_for_task_from_job_list!(batch_client, output, job_ids, remaining_tasks, 
                timeout, task_timeout, temp_blobs, orig_blobs, original_job_id, num_restart=num_restart)
            output_ref2 = wait_for_task_from_job_list!(batch_client, output, job_ids, remaining_tasks, 
                timeout, task_timeout, temp_blobs, orig_blobs, original_job_id, num_restart=num_restart)

            # Submit summation as new batch job (non-blocking) and add to pending tasks/jobs
            task_name = join(["task_", randstring(12)])
            bctrl = @batchexec(remote_reduction(output_ref1, output_ref2), Options(job_name="batch_reduce", 
                task_name=task_name, priority=100, pool=pool_no, reset_mpi=true))
            push!(remaining_tasks, bctrl.task_id[1]); push!(job_ids, bctrl.job_id[1]); push!(output, bctrl.output[1])

            # If only task is left -> fetch it, clean up and return it
            if length(remaining_tasks) == 1
                return job_ids[1], remaining_tasks[1], output[1], orig_blobs, temp_blobs
            end
        end
    end
end


# Inplace Fetch-reduce for output tuple (one temp. copy of output argument)
"""
    output = fetchreduce!(batch_controller::BatchController, output; op=+, destroy_blob=false, timeout=60)

 Fetch the output from the batch job in-place and apply the specified reduction operation to 
 the provided `output` (across tasks).


 *Input*:

 - `batch_controller` (BatchController): Batch control structure

 - `output`: Output arguments of executed batch function which will be overwritten.

 - `op`: Algebraic operation to apply to the output from different tasks.

 - `destroy_blob` (Bool): Remove the original blob upon successful fetching (default is `false`)

 - `timeout`: Timeout in minutes.

 - `num_restart`: Allowed retries for failed tasks (default is `0`).


 *Output*:

 - `output`: Return argument(s) of executed function after application of reduction operation (along tasks)
 
"""
function fetchreduce!(batch_controller::BatchController, output::Tuple; op=+, destroy_blob=true, timeout=60, 
    task_timeout=60, num_restart=0)

    # Single task: simply fetch output
    if batch_controller.num_tasks == 1
        temp = fetch!(batch_controller)
        for (i, entry) in enumerate(output)
            if ~isnothing(entry)
                entry[:] = temp[i]
            end
        end

    # Multiple tasks: fetch and sum output
    else

        remaining_tasks = deepcopy(batch_controller.task_id)
        task_id = nothing

        __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
        while true

            # Wait for one task from task list to finish
            try
                task_id = wait_for_one_task_from_multi_pool(batch_controller.batch_client, batch_controller.job_id, remaining_tasks;
                    task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
            catch
                throw("Reached timeout for task completion.")
            end
            __verbose__ && print("\nFetch output from task $task_id")

            # Fetch its output
            task_no = findall(i -> i["taskname"] == task_id, batch_controller.task_id)[1]
            if ~isempty(remaining_tasks)

                # Fetch output
                temp = fetch!(batch_controller, task_no; destroy_blob=destroy_blob, timeout=timeout, 
                    wait_for_completion=false)
                for (i, entry) in enumerate(output)
                    if ~isnothing(entry) && ~isnothing(temp)
                        entry[:] = broadcast(op, entry, temp[i])
                    end
                end
                
                # Remove task from task list
                local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]
                popat!(remaining_tasks, local_id)
            end

            # Return it task list is empty
            if isempty(remaining_tasks)
                __verbose__ && print("\n")
                if length(output) > 1
                    return output
                else
                    return output[1]
                end
            end
        end
    end
end

# Inplace fetch-reduce for single output argument
function fetchreduce!(batch_controller::BatchController, output; op=+, destroy_blob=true, timeout=60, task_timeout=60,
    num_restart=0)

    # Single task: simply fetch output
    if batch_controller.num_tasks == 1
        if ~isnothing(output)
            output[:] = fetch!(batch_controller)
        end

    # Multiple tasks: fetch and sum output
    else

        remaining_tasks = deepcopy(batch_controller.task_id)
        task_id = nothing

        __verbose__ && print("Monitoring tasks for 'Completed' state, timeout in $timeout minutes ...")
        while true

            # Wait for one task from task list to finish
            try
                task_id = wait_for_one_task_from_multi_pool(batch_controller.batch_client, batch_controller.job_id, remaining_tasks;
                    task_timeout=task_timeout, fetch_timeout=timeout, verbose=__verbose__, num_restart=num_restart)[1]
            catch
                throw("Reached timeout for task completion.")
            end
            __verbose__ && print("\nFetch output from task $task_id")

            # Fetch its output
            task_no = findall(i -> i["taskname"] == task_id, batch_controller.task_id)[1]
            if ~isempty(remaining_tasks)

                # Fetch output
                temp = fetch!(batch_controller, task_no; destroy_blob=destroy_blob, timeout=timeout, 
                    wait_for_completion=false)
                if ~isnothing(output) && ~isnothing(temp)
                    output[:] = broadcast(op, output, temp)
                end
                
                # Remove task from task list
                local_id = findall(i -> i["taskname"] == task_id, remaining_tasks)[1]
                popat!(remaining_tasks, local_id)
            end

            # Return it task list is empty
            if isempty(remaining_tasks)
                __verbose__ && print("\n")
                if length(output) > 1
                    return output
                else
                    return output[1]
                end
            end
        end
    end
end
