# Pyinterface for testing purposes that avoids any Azure API calls that require authentication or invoke cost
# Philipp A. Witte, Microsoft
# November 2020
#

create_batch_client(credentials::Nothing) = nothing

create_blob_client(credentials::Nothing) = nothing

create_queue_client(credentials::Nothing) = nothing


function create_clients(credentials::Nothing; batch::Bool=false, blob::Bool=false, queue::Bool=false)

    # List of all clients
    clients = Array{Any}(undef, 0)

    batch ? (batch_client = create_batch_client(credentials)) : batch_client = nothing
    blob ? (blob_client = create_blob_client(credentials)) : blob_client = nothing
    queue ? (queue_client = create_queue_client(credentials)) : queue_client = nothing
    
    return [Dict(
        "batch_client" => batch_client,
        "blob_client" => blob_client,
        "queue_client" => queue_client
        )]
end


###################################################################################################
# Blob stuff


# Create containers given a list of container names
create_blob_containers(blob_client::Nothing, container_name_list::Array{String, 1}) = nothing

create_batch_output_file(blob_client::Nothing, storage_account_name, container_name, filename) = nothing

###################################################################################################
# Batch stuff

# Create pool
function create_pool(batch_service_client::Nothing, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
    node_os_offer, node_os_sku; image_resource_id=nothing, resource_files=nothing,
    enable_auto_scale=false, auto_scale_formula=nothing, auto_scale_evaluation_interval_minutes=nothing)

    return nothing
end

# Create pool and resource file
function create_pool_and_resource_file(clients::Dict{String,Nothing}, pool_id, pool_vm_size, pool_node_count, 
    node_os_publisher, node_os_offer, node_os_sku, file_name, container_name; image_resource_id=nothing, 
    enable_auto_scale=false, auto_scale_formula=nothing, auto_scale_evaluation_interval_minutes=15)

    return nothing
end

# Enable auto scaling for batch pool
enable_auto_scale(batch_client::Nothing, pool_id, auto_scale_formula; auto_scale_evaluation_interval_minutes=5) = nothing

# Resize pool
resize_pool(batch_client::Nothing, pool_id, target_dedicated_nodes, target_low_priority_nodes; 
    resize_timeout_minutes=nothing, node_deallocation_option=nothing, pool_resize_options=nothing) = nothing


# Create resource file from file
create_batch_resource_from_file(blob_client::Nothing, container, file) = [nothing]


# Create resource file from existing blob
create_batch_resource_from_blob(blob_client::Nothing, container, blob) = [nothing]


# Create resource file from bytes
create_batch_resource_from_bytes(blob_client::Nothing, container, blob_name, blob) = [nothing]


# Create batch job
create_batch_job(batch_client::Nothing, job_id, pool_id; uses_task_dependencies=false, priority=0) = nothing

# Wait for all tasks to complete
wait_for_tasks_to_complete(batch_service_client::Nothing, job_id, timeout) = true

# Wait for specified task to complete
wait_for_task_to_complete(batch_service_client::Nothing, job_id, task_id, timeout) = true

# Wait for one task from a list of tasks to complete
function wait_for_one_task_to_complete(batch_service_client::Array{Nothing,1}, job_id, task_id_list, timedelta_minutes)
    idx = randperm(length(task_id_list))[1]    # return random index from task list
    return task_id_list[idx]
end

function wait_for_one_task_from_multi_pool(batch_service_client::Array{Nothing,1}, job_id, task_id_list, timedelta_minutes)
    idx = randperm(length(task_id_list))[1]
    task_id = task_id_list[idx]["taskname"]    # return random index from task list
    pool_id = task_id_list[idx]["pool"]
    return task_id, pool_id
end

function wait_for_one_task_from_multi_jobs(batch_service_client::Array{Nothing,1}, job_id_list, task_id_list, timedelta_minutes)
    idx = randperm(length(task_id_list))
    task_id = task_id_list[idx]["taskname"]    # return random index from task list
    pool_id = task_id_list[idx]["pool"]
    return task_id, pool_id
end
