#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

###################################################################################################
# Batch definition


# Assign available batch + blob clients to available pools
function divide_clients_among_pools()
    num_pools = parse(Int, __params__["_POOL_COUNT"])
    num_credentials = length(__credentials__)

    if num_pools == num_credentials
        return __credentials__, __clients__, __resources__
    elseif num_pools < num_credentials
        return __credentials__[1:num_pools], __clients__[1:num_pools], __resources__[1:num_pools]
    else
        credentials = Array{Any}(undef, 0)
        clients = Array{Any}(undef, 0)
        resources = Array{Any}(undef, 0)
        count = 1
        for i=1:num_pools
            push!(credentials, __credentials__[count])
            push!(clients, __clients__[count])
            push!(resources, __resources__[count])
            if count >= num_credentials
                count = 1
            else
                count += 1
            end
        end
        return credentials, clients, resources
    end
end


"""
    `create_pool(; enable_auto_scale=false, auto_scale_formula=nothing, 
    auto_scale_evaluation_interval_minutes=nothing, image_resource_id=nothing)`

 Create a batch pool using parameters specified in as a JSON file. E.g. set `ENV["PARAMETERS"] = "parameters.json"` to 
 point to the parameter file.


 *Optional arguments*:

 - `enable_auto_scale` (Bool): Enable auto-scaling of the pool. Requires the `auto_scale_formula` and 
    `auto_scale_evaluation_interval_minutes` to be set. If the number of VMs in the pool cannot be specified.

 - `auto_scale_formula` (String): Formula for auto-scaling the pool. 
    See "https://docs.microsoft.com/en-us/azure/batch/batch-automatic-scaling" for details.

 - `image_resource_id` (String): Image ID of the VM image.


 *Output*:

 - `Nothing`
 
 See also:  [`create_pool_and_resource_file`](@ref)
 """
function create_pool(; enable_auto_scale=false, auto_scale_formula=nothing, 
    auto_scale_evaluation_interval_minutes=nothing, image_resource_id=nothing, 
    container_registry=nothing)

    # Autoscaling?
    if enable_auto_scale
        num_nodes = nothing
    else
        num_nodes = __params__["_NODE_COUNT_PER_POOL"]
    end

    # Internode?
    enable_inter_node = parse(Bool, __params__["_INTER_NODE_CONNECTION"])

    # Container?
    if __params__["_CONTAINER"] == "None"
        docker_container = nothing
    else
        docker_container = __params__["_CONTAINER"]
    end

    # Divide clients among pools
    credential_per_pool, clients_per_pool, resources_per_pool = divide_clients_among_pools()
    num_pools = parse(Int, __params__["_POOL_COUNT"])

    for i=1:num_pools
        pool_id = join([__params__["_POOL_ID"], "_", i])
        try
            azureclusterlesshpc.create_pool(clients_per_pool[i]["batch_client"], pool_id, __params__["_POOL_VM_SIZE"], num_nodes, 
                __params__["_NODE_OS_PUBLISHER"], __params__["_NODE_OS_OFFER"], __params__["_NODE_OS_SKU"],
                enable_inter_node=enable_inter_node, enable_auto_scale=enable_auto_scale, auto_scale_formula=auto_scale_formula, 
                auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes, image_resource_id=image_resource_id,
                container=docker_container, container_registry=container_registry)

            # Keep track of active pools
            print(join(["Created pool ", i ," of ", num_pools, " in ", credential_per_pool[i]["_REGION"], " with ", num_nodes, " nodes.\n"]))
            push!(__active_pools__, Dict("pool_id" => pool_id, "clients" => clients_per_pool[i], "credentials" => credential_per_pool[i],
                "resources" => resources_per_pool[i]))
        catch
            print(join(["Pool ", i ," of ", num_pools, " in ", credential_per_pool[i]["_REGION"]," already exists.\n"]))
            push!(__active_pools__, Dict("pool_id" => pool_id, "clients" => clients_per_pool[i], "credentials" => credential_per_pool[i],
                "resources" => resources_per_pool[i]))
        end
    end
end


"""
    `create_pool_and_resource_file(startup_script; enable_auto_scale=false, auto_scale_formula=nothing, 
    auto_scale_evaluation_interval_minutes=nothing, image_resource_id=nothing)`

 Create a batch pool using a given startup script that will be executed by nodes joining the pool. The pool parameters are specified 
 in a separate JSON file. E.g. set `ENV["PARAMETERS"] = "parameters.json"` to point to the parameter file.


 *Required arguments*:

 - `startup_script` (String): Path to a bash script that is executed by nodes joining the batch pool.


 *Optional arguments*:

 - `enable_auto_scale` (Bool): Enable auto-scaling of the pool. Requires the `auto_scale_formula` and 
    `auto_scale_evaluation_interval_minutes` to be set. If the number of VMs in the pool cannot be specified.

 - `auto_scale_formula` (String): Formula for auto-scaling the pool. 
    See "https://docs.microsoft.com/en-us/azure/batch/batch-automatic-scaling" for details.

 - `image_resource_id` (String): Image ID of the VM image.


 *Output*:

 - `Nothing`
 
 See also:  [`create_pool`](@ref)
 """
function create_pool_and_resource_file(startup_script; enable_auto_scale=false, auto_scale_formula=nothing,
    auto_scale_evaluation_interval_minutes=nothing, image_resource_id=nothing)

    # Create container if it doesn't exist
    for client in __clients__
        create_blob_containers(client["blob_client"], [__container__])
    end
    if enable_auto_scale
        num_nodes = nothing
    else
        num_nodes = __params__["_NODE_COUNT_PER_POOL"]
    end
   
    # Enable inter node connection?
    enable_inter_node = parse(Bool, __params__["_INTER_NODE_CONNECTION"])

    # Container?
    if __params__["_CONTAINER"] == "None"
        docker_container = nothing
    else
        docker_container = __params__["_CONTAINER"]
    end

    # Divide clients among pools
    credential_per_pool, clients_per_pool, resources_per_pool = divide_clients_among_pools()
    num_pools = parse(Int, __params__["_POOL_COUNT"])

    for i=1:num_pools
        pool_id = join([__params__["_POOL_ID"], "_", i])
        try
            azureclusterlesshpc.create_pool_and_resource_file(clients_per_pool[i], pool_id, __params__["_POOL_VM_SIZE"], num_nodes, 
                __params__["_NODE_OS_PUBLISHER"], __params__["_NODE_OS_OFFER"], __params__["_NODE_OS_SKU"], startup_script, __container__; 
                enable_inter_node=enable_inter_node, enable_auto_scale=enable_auto_scale, auto_scale_formula=auto_scale_formula, 
                auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes, image_resource_id=image_resource_id,
                container=docker_container)

            # Keep track of active pools
            print(join(["Created pool ", i ," of ", num_pools, " in ", credential_per_pool[i]["_REGION"], " with ", num_nodes, " nodes.\n"]))
            push!(__active_pools__, Dict("pool_id" => pool_id, "clients" => clients_per_pool[i], "credentials" => credential_per_pool[i],
                "resources" => resources_per_pool[i]))
        catch
            print(join(["Pool ", i ," of ", num_pools, " in ", credential_per_pool[i]["_REGION"]," already exists.\n"]))
            push!(__active_pools__, Dict("pool_id" => pool_id, "clients" => clients_per_pool[i], "credentials" => credential_per_pool[i],
                "resources" => resources_per_pool[i]))
        end
    end
end