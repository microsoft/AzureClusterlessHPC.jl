#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

# Exports
export create_batch_client, create_blob_client, create_queue_client, create_clients
export create_blob_containers, create_pool_and_resource_file, resize_pool, create_pool
export create_batch_resource_from_file, create_batch_resource_from_bytes, create_batch_resource_from_blob
export create_batch_job, create_batch_task, submit_batch_job, create_batch_env
export wait_for_tasks_to_complete, wait_for_task_to_complete#, wait_for_one_task_to_complete
export create_batch_output_file, create_task_constraint, enable_auto_scale, create_batch_envs
export wait_for_one_task_from_multi_jobs, wait_for_one_task_from_multi_pool
export upload_bytes_to_container, create_blob_url, create_batch_resource_from_blob_url


###################################################################################################
# Wrappers around Python credential functions

function create_batch_client(credentials::Dict{String, Any})
    return azureclusterlesshpc.create_batch_client(credentials)
end


function create_blob_client(credentials::Dict{String, Any})
    return azureclusterlesshpc.create_blob_client(credentials)
end


function create_queue_client(credentials::Dict{String, Any})
    return azureclusterlesshpc.queue_blob_client(credentials)
end


function create_clients(credentials::Dict{String, Any}; batch::Bool=false, blob::Bool=false, queue::Bool=false)

    batch ? (batch_client = create_batch_client(credentials)) : batch_client = nothing
    blob ? (blob_client = create_blob_client(credentials)) : blob_client = nothing
    queue ? (queue_client = create_queue_client(credentials)) : queue_client = nothing
    
    return [Dict(
        "batch_client" => batch_client,
        "blob_client" => blob_client,
        "queue_client" => queue_client
        )]
end

function create_clients(credential_list::Array; batch::Bool=false, blob::Bool=false, queue::Bool=false)

    # List of all clients
    clients = Array{Any}(undef, 0)

    for credential in credential_list

        batch ? (batch_client = create_batch_client(credential)) : batch_client = nothing
        blob ? (blob_client = create_blob_client(credential)) : blob_client = nothing
        queue ? (queue_client = create_queue_client(credential)) : queue_client = nothing
        
        cred = Dict(
            "batch_client" => batch_client,
            "blob_client" => blob_client,
            "queue_client" => queue_client
            )

        push!(clients, cred)
    end
    return clients
end

###################################################################################################
# Blob stuff


create_blob_url(blob_client::PyObject, container_name, blob_list) = 
    azureclusterlesshpc.create_blob_url(blob_client, container_name, blob_list)

upload_bytes_to_container(blob_client::PyObject, container_name, blob_name, blob; verbose=true) = 
    azureclusterlesshpc.upload_bytes_to_container(blob_client, container_name, blob_name, blob; verbose=verbose)

# Create containers given a list of container names
create_blob_containers(blob_client::PyObject, container_name_list::Array{String, 1}) =
    azureclusterlesshpc.create_blob_containers(blob_client, container_name_list)


create_batch_output_file(blob_client, storage_account_name, container_name, filename) =
    azureclusterlesshpc.create_batch_output_file(blob_client, storage_account_name, container_name, filename)


###################################################################################################
# Batch stuff

# Create pool
function create_pool(batch_service_client, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
    node_os_offer, node_os_sku; image_resource_id=nothing, enable_inter_node=false, resource_files=nothing,
    enable_auto_scale=false, auto_scale_formula=nothing, auto_scale_evaluation_interval_minutes=nothing,
    container=nothing, container_registry=nothing)

    azureclusterlesshpc.create_pool(batch_service_client, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
        node_os_offer, node_os_sku, image_resource_id=image_resource_id, enable_inter_node=enable_inter_node, 
        resource_files=resource_files, enable_auto_scale=enable_auto_scale, auto_scale_formula=auto_scale_formula, 
        auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes, container=container,
        container_registry=container_registry)
end

# Create pool and resource file
function create_pool_and_resource_file(clients, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
    node_os_offer, node_os_sku, file_name, container_name; image_resource_id=nothing, enable_inter_node=false,
    enable_auto_scale=false, auto_scale_formula=nothing, auto_scale_evaluation_interval_minutes=15, container=false,
    container_registry=nothing)

    azureclusterlesshpc.create_pool_and_resource_file(clients, pool_id, pool_vm_size, pool_node_count, 
        node_os_publisher, node_os_offer, node_os_sku, file_name, container_name, image_resource_id=image_resource_id,
        enable_inter_node=enable_inter_node, enable_auto_scale=enable_auto_scale, auto_scale_formula=auto_scale_formula,
        auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes, container=container,
        container_registry=container_registry)
end

# Enable auto scaling for batch pool
enable_auto_scale(batch_client, pool_id, auto_scale_formula; auto_scale_evaluation_interval_minutes=5) =
    azureclusterlesshpc.enable_auto_scale(batch_client, pool_id, auto_scale_formula, 
        auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes)


# Resize pool
resize_pool(batch_client, pool_id, target_dedicated_nodes, target_low_priority_nodes; 
    resize_timeout_minutes=nothing, node_deallocation_option=nothing, pool_resize_options=nothing) = 
    azureclusterlesshpc.resize_pool(batch_client, pool_id, target_dedicated_nodes, target_low_priority_nodes, 
        resize_timeout_minutes=resize_timeout_minutes, node_deallocation_option=node_deallocation_option, 
        pool_resize_options=pool_resize_options)

# Create resource from url
create_batch_resource_from_blob_url(shared_url, shared_blob) = 
    azureclusterlesshpc.create_batch_resource_from_blob_url(shared_url, shared_blob)


# Create resource file from file
create_batch_resource_from_file(blob_client, container, file; verbose=true) = 
    azureclusterlesshpc.create_batch_resource_from_file(blob_client, container, file, verbose=verbose)


# Create resource file from existing blob
create_batch_resource_from_blob(blob_client, container, blob) = 
    azureclusterlesshpc.create_batch_resource_from_blob(blob_client, container, blob)


# Create resource file from bytes
create_batch_resource_from_bytes(blob_client, container, blob_name, blob; verbose=true) =
    azureclusterlesshpc.create_batch_resource_from_bytes(blob_client, container, blob_name, blob, verbose=verbose)


# Create batch job
create_batch_job(batch_client, job_id, pool_id; uses_task_dependencies=false, priority=0, verbose=true) = 
    azureclusterlesshpc.create_batch_job(batch_client, job_id, pool_id, uses_task_dependencies=uses_task_dependencies,
        priority=priority, verbose=verbose)


# Create tasks for batch job
create_batch_task(; resource_files=nothing, environment_variables=nothing, application_cmd=nothing,
    output_files=nothing, taskname="task", task_constraints=nothing, num_nodes_per_task=1, docker_container=nothing) =     
    azureclusterlesshpc.create_batch_task(resource_files=resource_files, environment_variables=environment_variables, 
        application_cmd=application_cmd, output_files=output_files, taskname=taskname, task_constraints=task_constraints, 
        num_nodes_per_task=num_nodes_per_task, docker_container=docker_container)

    
# Create task constraints
create_task_constraint(; max_wall_clock_time=nothing, retention_time=nothing, max_task_retry_count=0) = 
    azureclusterlesshpc.create_task_constraint(max_wall_clock_time=max_wall_clock_time, retention_time=retention_time, 
        max_task_retry_count=max_task_retry_count)


# Wait for all tasks to complete
wait_for_tasks_to_complete(batch_service_client, job_id;  task_timeout=60, fetch_timeout=60, verbose=true, num_restart=0) = 
    azureclusterlesshpc.wait_for_tasks_to_complete(batch_service_client, job_id, task_timeout=task_timeout, 
        fetch_timeout=fetch_timeout, verbose=verbose, num_restart=num_restart)


# Wait for specified task to complete
wait_for_task_to_complete(batch_service_client, job_id, task_id, timeout; verbose=true, num_restart=0) = 
    azureclusterlesshpc.wait_for_task_to_complete(batch_service_client, job_id, task_id, timeout, verbose=verbose,
    num_restart=num_restart)
    

# Wait for one task from a list of tasks to complete
wait_for_one_task_from_multi_pool(batch_service_client, job_id, task_id_list;
    task_timeout=60, fetch_timeout=60, verbose=true, num_restart=0) = 
    azureclusterlesshpc.wait_for_one_task_from_multi_pool(batch_service_client, job_id, task_id_list, 
    task_timeout=task_timeout, fetch_timeout=fetch_timeout, verbose=verbose, num_restart=num_restart)


wait_for_one_task_from_multi_jobs(batch_service_client, job_id_list, task_id_list;
    task_timeout=60, fetch_timeout=60, verbose=true, num_restart=0) =
    azureclusterlesshpc.wait_for_one_task_from_multi_jobs(batch_service_client, job_id_list, task_id_list, 
    task_timeout=task_timeout, fetch_timeout=fetch_timeout, verbose=verbose, num_restart=num_restart)

# Create batch environment variable
create_batch_env(name, value) = azureclusterlesshpc.create_batch_env(name, value)
create_batch_envs(names, values) = azureclusterlesshpc.create_batch_envs(names, values)