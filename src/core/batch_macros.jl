#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

###################################################################################################
# Exports

export @batchdef, @bcast, @batchexec
export create_bcast_batch_resource, submit_batch_job, eval_symbol_get_index!
export replace_symbol_in_expression!, create_batch_resource_from_blob_future
export create_batch_resource_for_blob_future_in_ast, assign_tasks_per_pool


###################################################################################################
# Code collection

# Collect @batchdef expressions in global vars
function append_batchdef_expression(expr)

    linefilter!(expr)
    # If expression is "include" statement, add file to batch resources

    linefilter!(expr)
    if expr.args[1] == :include || expr.args[1] == :fileinclude
        for (client, resource) in zip(__clients__, __resources__)
            create_blob_containers(client["blob_client"], [__container__]) # if not exist
            push!(resource, create_batch_resource_from_file(client["blob_client"], __container__, expr.args[2];
                verbose=__verbose__)[1])
        end
        expr.args[end] = convert(String, split(expr.args[end], "/")[end])    # remove path
    end

    # If expressing is "using" statement, collect separately in __packages__ variable, else append to __expressions__
    if expr.head == :using
        ex0 = :(@everywhere); push!(ex0.args, expr); linefilter!(ex0)
        if isnothing(__packages__)
            global __packages__ = Expr(:block, ex0)
        else
            push!(__packages__.args, ex0)
        end
    elseif expr.args[1] != :fileinclude
        ex0 = :(@everywhere); push!(ex0.args, expr); linefilter!(ex0)
        # Append expression to AST
        if isnothing(__expressions__)
            global __expressions__ = Expr(:block, ex0)
        else
            push!(__expressions__.args, ex0)
        end
    end
end


###################################################################################################
# Submit batch job


# Scan AST and create batch resource file for blob futures
function create_batch_resource_for_blob_future_in_ast(expr, pool_no, blob_futures)

    # Reached leaf
    if typeof(expr) != Expr
        return
    elseif expr.head == :call && length(expr.args) == 1
        return
    end

    for (i, arg) in enumerate(expr.args)
        if typeof(arg) == BlobFuture
            typeof(arg.blob) != BlobRef && 
                throw("BlobFuture does not contain a blob reference. Possibly, fetch! was already called on the reference.")
            create_batch_resource_from_blob_future(arg, pool_no, blob_futures)
        elseif typeof(arg) == Expr
            create_batch_resource_for_blob_future_in_ast(expr.args[i], pool_no, blob_futures)
        end
    end
end

function create_batch_resource_from_blob_future(blob_future::BlobFuture, pool_no, blob_futures)
    for blob in blob_future.blob.name
        push!(blob_futures, create_batch_resource_from_blob(__active_pools__[pool_no]["clients"]["blob_client"], blob_future.container, blob)[1])
    end
end


function create_batch_resource_for_batch_future_in_ast(expr, pool_no, batch_futures)

    # Reached leaf
    if typeof(expr) != Expr
        return
    elseif expr.head == :call && length(expr.args) == 1
        return
    end

    for (i, arg) in enumerate(expr.args)
        if typeof(arg) == BatchFuture
            typeof(arg.blob) != BlobRef && 
                throw("BatchFuture does not contain a blob reference. Possibly, fetch! was already called on the reference.")
            create_batch_resource_from_batch_future(arg, pool_no, batch_futures)
        elseif typeof(arg) == Expr
            create_batch_resource_for_batch_future_in_ast(expr.args[i], pool_no, batch_futures)
        end
    end
end

function create_batch_resource_from_batch_future(batch_future::BatchFuture, pool_no, batch_futures)
    url = create_blob_url(__active_pools__[pool_no]["clients"]["blob_client"], 
        batch_future.container, [batch_future.blob.name])
    push!(batch_futures, create_batch_resource_from_blob_url(url, [batch_future.blob.name])[1])
end


function create_batch_task!(expr, pool_no, count, tasks, resources, task_ids, output, app_cmd, options)

    # Append expressions previously tagged via @batchdef
    isnothing(options) ? (task_base = "task_") : (task_base = options.task_name)
    push!(task_ids, Dict("taskname" => join([task_base, count]), "pool" => pool_no))
    if isnothing(__expressions__)
        expressions = expr
    else
        expressions = deepcopy(__expressions__)
        push!(expressions.args, expr)
    end

    # Replace return statement with serialization and create batch output resources
    filenames = []; outfiles = Array{PyObject}(undef, 0)
    funcname = expr.args[1] # name of function that is called remotely
    find_function_in_ast_and_replace_return!(expressions, funcname, filenames)
    for outfile in filenames
        push!(outfiles, create_batch_output_file(__active_pools__[pool_no]["clients"]["blob_client"], 
            __active_pools__[pool_no]["credentials"]["_STORAGE_ACCOUNT_NAME"], 
            __container__, outfile)...)
    end

    # Collect output blob names in Julia Futures
    future = BlobFuture(__container__, BlobRef(tuple(filenames...)), pool_no)
    push!(output, future)

    # Serialize AST
    filename = join([task_base, count, ".dat"])
    iostream = IOBuffer(); serialize(iostream, linefilter!(expressions))

    # Environment variables
    if ~isnothing(options) && options.reset_mpi == true
        env_num_nodes_per_task = "1"
        env_num_procs_per_node = "1"
    else
        env_num_nodes_per_task = __params__["_NUM_NODES_PER_TASK"]
        env_num_procs_per_node = __params__["_NUM_PROCS_PER_NODE"]
    end
    envs = create_batch_envs(
        ["FILENAME", "JULIA_DEPOT_PATH", "PYTHONPATH", "MPI_RUN", "INTER_NODE_CONNECTION", "NUM_NODES_PER_TASK",
        "NUM_PROCS_PER_NODE", "OMP_NUM_THREADS", "JULIA_NUM_THREADS"], [filename, __params__["_JULIA_DEPOT_PATH"], 
        __params__["_PYTHONPATH"], __params__["_MPI_RUN"], __params__["_INTER_NODE_CONNECTION"], 
        env_num_nodes_per_task, env_num_procs_per_node, __params__["_OMP_NUM_THREADS"],
        __params__["_JULIA_NUM_THREADS"]])

    # Create resource file and append to resource list
    ast_resource = create_batch_resource_from_bytes(__active_pools__[pool_no]["clients"]["blob_client"], __container__, filename, iostream.data; verbose=__verbose__)
    length(__active_pools__[pool_no]["resources"]) > 0 && (ast_resource = vcat(ast_resource, __active_pools__[pool_no]["resources"]))

    # Create resource file for blob futures in AST
    blob_futures = Array{PyCall.PyObject, 1}()
    create_batch_resource_for_blob_future_in_ast(expr, pool_no, blob_futures)
    length(blob_futures) > 0 && (ast_resource = vcat(ast_resource, blob_futures))

    # Create resource file for batch futures in AST
    batch_futures = Array{PyCall.PyObject, 1}()
    create_batch_resource_for_batch_future_in_ast(expr, pool_no, batch_futures)
    length(batch_futures) > 0 && (ast_resource = vcat(ast_resource, batch_futures))

    # Create tasks and submit job
    task_constraints = create_task_constraint(max_task_retry_count=parse(Int, __params__["_NUM_RETRYS"]))
    num_nodes_per_task=parse(Int,__params__["_NUM_NODES_PER_TASK"])
    __params__["_CONTAINER"] == "None" ? (docker_container = nothing) : (docker_container = __params__["_CONTAINER"])
    push!(tasks, create_batch_task(resource_files=vcat(resources, ast_resource), application_cmd=app_cmd, task_constraints=task_constraints,
        environment_variables=envs, output_files=outfiles, taskname=task_ids[end]["taskname"], num_nodes_per_task=num_nodes_per_task,
        docker_container=docker_container))
end


# Split list of task expressions according to schedule
function split_expressions(expression_list, task_list_per_pool)

    # Find pools with tasks in it
    idx = findall(i -> i != 0:0, task_list_per_pool)
    num_pools_active = length(idx)
    expressions_per_pool = Array{Any}(undef, num_pools_active)
    pool_no = Array{Any}(undef, num_pools_active)

    for i=1:num_pools_active
        expressions_per_pool[i] = expression_list[task_list_per_pool[idx[i]]]
        pool_no[i] = idx[i]
    end
    return expressions_per_pool, idx
end


# Assign range of tasks to each batch pool
function assign_tasks_per_pool(num_tasks; strategy="chunk", options=nothing)

    # Distribute tasks among available pools
    ~isnothing(options) && ~isnothing(options.pool) ? pool_no = options.pool : pool_no = nothing
    num_pools = length(__active_pools__)
    if num_pools == 0
        @warn "No active pools found. Tasks will be submitted but cannot be executed."
        num_pools = parse(Int, __params__["_POOL_COUNT"])
    end
    if strategy == "chunk"

        # Split into even chunks
        min_tasks = Int(floor(num_tasks/num_pools))
        leftover_tasks = mod(num_tasks, num_pools)
        tasks_per_worker = Array{Any}(undef, num_pools)
        for i=1:num_pools
            tasks_per_worker[i] = min_tasks
            if i <= leftover_tasks
                tasks_per_worker[i] += 1
            end
        end

        task_list_per_pool = Array{Any}(undef, num_pools)
        if ~isnothing(pool_no)
            # Assign all tasks to specified pool
            for j=1:num_pools 
                task_list_per_pool[j] = 0:0
            end
            task_list_per_pool[pool_no] = 1:num_tasks
        else
            count = 0
            for i=1:num_pools
                if count < num_tasks
                    task_list_per_pool[i] = count+1:count+tasks_per_worker[i]
                else
                    task_list_per_pool[i] = 0:0
                end
                count += tasks_per_worker[i]
            end
        end
    else
        throw("Specified stragety not supported.")
    end
    return task_list_per_pool
end


# Submit multi-task batch job
function submit_batch_job(expression_list; options=nothing)    

    num_tasks = length(expression_list)

    # CMD, job id and priority
    app_cmd = "/bin/bash -c \'set -e; set -o pipefail; \$AZ_BATCH_TASK_WORKING_DIR/application-cmd; wait\'"
    ~isnothing(options) ? (base_name = options.job_name) : (base_name = __params__["_JOB_ID"])
    job_base = join([base_name, "_", objectid(expression_list)])
    ~isnothing(options) ? (priority = options.priority) : (priority = 0)

    # Split expressions among available batch pools
    task_list_per_pool =  assign_tasks_per_pool(num_tasks; strategy="chunk", options=options)
    expressions_per_pool, pool_numbers = split_expressions(expression_list, task_list_per_pool)

    output = []; task_ids = []; count = 1; job_ids = []
    for (i, expressions) in enumerate(expressions_per_pool)

        pool_no = pool_numbers[i]
        push!(job_ids, join([job_base, "_", i]))
        create_batch_job(__active_pools__[pool_no]["clients"]["batch_client"], job_ids[end], 
            __active_pools__[pool_no]["pool_id"]; uses_task_dependencies=false, priority=priority, verbose=__verbose__)
        create_blob_containers(__active_pools__[pool_no]["clients"]["blob_client"], [__container__])

        # Add Julia runtime and cmd to batch resource list
        resources = Array{PyObject}(undef, 0)
        push!(resources, create_batch_resource_from_file(__active_pools__[pool_no]["clients"]["blob_client"], 
            __container__, joinpath(dirname(pathof(AzureClusterlessHPC)), "runtime/application-cmd"); 
            verbose=__verbose__)[1])  
        push!(resources, create_batch_resource_from_file(__active_pools__[pool_no]["clients"]["blob_client"],
            __container__, joinpath(dirname(pathof(AzureClusterlessHPC)), "runtime/batch_runtime.jl");
            verbose=__verbose__)[1])

        # Serialize expressions with "using ..." and create batch resource
        if ~isnothing(__packages__)
            iostream = IOBuffer(); serialize(iostream, __packages__)
            push!(resources, create_batch_resource_from_bytes(__active_pools__[pool_no]["clients"]["blob_client"], 
                __container__, "packages.dat", iostream.data; verbose=__verbose__)[1])
        end
        
        # Create tasks for each batch pool
        tasks = []
        @sync begin
            for (j, expr) in enumerate(expressions)
                create_batch_task!(expr, pool_no, count, tasks, resources, task_ids, output, app_cmd, options)
                count += 1
            end
        end
        if ~isnothing(__active_pools__[pool_no]["clients"]["batch_client"])
            __active_pools__[pool_no]["clients"]["batch_client"].task.add_collection(job_ids[end], tasks)
        end
    end
    return BatchController(job_ids, task_ids, length(expression_list), output)
end



#######################################################################################################################
# Capture runtime args and create job submission

# Set index methods for expressions
function setindex!(expr::Expr, val, i)
    expr.args[i] = val
end

function setindex!(expr::Expr, val, i::Array)
    if length(i) == 1
        expr.args[i[1]] = val
    elseif length(i) == 2
        expr.args[i[1]].args[i[2]] = val
    elseif length(i) == 3
        expr.args[i[1]].args[i[2]].args[i[3]] = val
    elseif length(i) == 4
        expr.args[i[1]].args[i[2]].args[i[2]].args[i[4]] = val
    elseif length(i) == 5
        expr.args[i[1]].args[i[2]].args[i[2]].args[i[4]].args[i[5]] = val
    end
end

# Find symbols
function locate_symbols!(expr, level, locations, symbols; symbol_exception=nothing)

    # Reached leaf
    if typeof(expr) != Expr
        return
    elseif expr.head == :call && length(expr.args) == 1
        return
    end

    # Recursively step through AST and find symbols that are neither function nor kwarg names
    (expr.head == :call || expr.head == :kw) ? (start=2) : (start=1)
    for j=start:length(expr.args)
        if typeof(expr.args[j]) == Symbol
            # Dont add iterate from pmap to collection
            if isnothing(symbol_exception) || expr.args[j] != symbol_exception
                push!(symbols, expr.args[j])
                push!(locations, vcat(level, j))
            end
            # To do: don't replace symbols of functions passed as args
        elseif typeof(expr.args[j]) == Expr
            new_level = deepcopy(level)
            push!(new_level, j)
            locate_symbols!(expr.args[j], new_level, locations, symbols; symbol_exception=symbol_exception)
        end
    end
end

# Replace given symbol with value in expression
function replace_symbol_in_expression!(expr, symbol, val)
    if typeof(expr) == Expr
        for (i, arg) in enumerate(expr.args)
            if typeof(arg) == Expr
                replace_symbol_in_expression!(expr.args[i], symbol, val)
            elseif typeof(arg) == Symbol
                if arg == symbol
                    expr.args[i] = val
                end
            end
        end
    end
end


# If symbol is indexed, extract indexed value
function eval_symbol_get_index!(expr)
    if typeof(expr) == Expr
        for (i, arg) in enumerate(expr.args)
            if typeof(arg) == Expr && arg.head == :ref
                expr.args[i] = arg.args[1][arg.args[2:end]...]
            elseif typeof(arg) == Expr
                eval_symbol_get_index!(expr.args[i])
            end
        end
    end
end


# Create list of expressions for multi-task batch job
function create_multi_task_expression_list_pmap(expr; options=nothing)

        # Index symbol and pmap argument collection
        index_symbol = expr.args[2].args[1]
        arg_collection = expr.args[3]

        # Find all symbols and their locations
        level = []; indices = []; symbols = []
        expr_i = deepcopy(expr.args[2].args[2].args[2])
        locate_symbols!(expr_i, level, indices, symbols; symbol_exception=index_symbol)

        # Base quote: deserialize expression + loop over tasks
        iostream = IOBuffer(); AzureClusterlessHPC.serialize(iostream, expr)
        expr_base = quote
            _expr = AzureClusterlessHPC.deserialize(IOBuffer($iostream.data))
            _expr_collection = []
            _index_symbol = _expr.args[2].args[1]
            _arg_collection = $arg_collection
            for (_i, _arg) in enumerate(_arg_collection)
                _expr_i = deepcopy(_expr.args[2].args[2].args[2])
                replace_symbol_in_expression!(_expr_i, _index_symbol, _arg)
            end
        end
        linefilter!(expr_base)

        # Loop over symbols
        for j=1:length(symbols)

            # Replace symbol
            symbol = symbols[j]
            idx = indices[j]
            expr_new = quote
                _expr_i[$idx] = $symbol
            end

            # Insert quote into task loop
            linefilter!(expr_new)
            push!(expr_base.args[5].args[2].args, expr_new.args...)
        end

        # Add expr to collection (inside task loop)
        expr_new = quote
            eval_symbol_get_index!(_expr_i)
            push!(_expr_collection, _expr_i)
        end
        linefilter!(expr_new)
        push!(expr_base.args[5].args[2].args, expr_new.args...)

        # Submit batch job for expression
        expr_new = quote
            @time submit_batch_job(_expr_collection; options=$options)  
        end
        linefilter!(expr_new)
        push!(expr_base.args, expr_new.args...)
        return expr_base
end

# Create expression for single-task batch job
function create_single_task_expression_list(expr; options=nothing)

    # Find all symbols and their locations
    level = []; indices = []; symbols = []
    locate_symbols!(expr, level, indices, symbols)
    
    # Base quote: deserialize expression
    iostream = IOBuffer(); AzureClusterlessHPC.serialize(iostream, expr)
    expr_base = quote
        _expr = AzureClusterlessHPC.deserialize(IOBuffer($iostream.data))
    end
    linefilter!(expr_base)

    # Loop over symbols
    for j=1:length(symbols)

        # Replace symbol
        symbol = symbols[j]
        idx = indices[j]
        expr_new = quote
            _expr[$idx] = $symbol
        end

        # Append to quote
        linefilter!(expr_new)
        push!(expr_base.args, expr_new.args...)
    end

    # Submit batch job for expression
    expr_new = quote
        eval_symbol_get_index!(_expr)   # eval get index functions
        submit_batch_job([_expr]; options=$options)
    end
    linefilter!(expr_new)
    push!(expr_base.args, expr_new.args...)
    return expr_base
end

# Create list of batch tasks from expression
function create_expression_to_submit_batch_job(expr; options=nothing)
    if expr.args[1] == :pmap
        expr_base = create_multi_task_expression_list_pmap(expr; options=options)
    else
        expr_base = create_single_task_expression_list(expr; options=options)
    end
    return expr_base
end


#######################################################################################################################
# Output

# Find "write" statements and collect them in "filenames"
function find_output_files!(expr, filenames)

    # Reached leaf
    if typeof(expr) != Expr
        return
    end

    # Recursively step through AST
    for i=1:length(expr.args)
        if typeof(expr.args[i]) == Expr
            if expr.args[i].args[1] == :write
                filename = randstring(12)   # create new random output filename as original filename may contain symbols
                expr.args[i].args[2] = filename
                push!(filenames, filename)
            else
                find_output_files!(expr.args[i], filenames)
            end
        end
    end
end

# Find return statement in expression and replace w/ serialization
function replace_return_with_serialization!(expr, filelist)
    typeof(expr) != Expr && return

    # Check if return is in current symbol block
    found_return_in_block = false
    idx = nothing
    for (i, arg) in enumerate(expr.args)
        if typeof(arg) == Expr && arg.head == :return
            found_return_in_block = true
            idx = i
        end
    end

    if found_return_in_block
        # Multiple return arguments or expression
        if typeof(expr.args[idx].args[1]) == Expr
            # Loop over return arguments
            for (i, argout) in enumerate(expr.args[idx].args[1].args)

                # Create random filename and add to collection
                filename = randstring(12)
                push!(filelist, filename)
                
                # Insert serialization at location of return statement
                insert!(expr.args, idx + (3*i-2), :(iostream = open($filename, "w")))
                insert!(expr.args, idx + (3*i-1), :(serialize(iostream, $argout)))
                insert!(expr.args, idx + 3*i, :(close(iostream)))
            end
        else
            argout = expr.args[idx].args[1]

            # Create random filename and add to collection
            filename = randstring(12)
            push!(filelist, filename)
            
            # Insert serialization at location of return statement
            insert!(expr.args, idx+1, :(iostream = open($filename, "w")))
            insert!(expr.args, idx+2, :(serialize(iostream, $argout)))
            insert!(expr.args, idx+3, :(close(iostream)))
        end
        # Remove return statement from block
        popat!(expr.args, idx)
    else
        # Step through AST
        for i=1:length(expr.args)
            if typeof(expr.args[i]) == Expr
                replace_return_with_serialization!(expr.args[i], filelist)
            end
        end
    end
end

# Replace return statement for given function with serialization
function find_function_in_ast_and_replace_return!(expr, fname, filelist)

    # Reached AST leaf
    typeof(expr) != Expr && return

    if expr.head == :function && expr.args[1].args[1] == fname
        # Found function with given name. Now replace return w/ serialization
        replace_return_with_serialization!(expr, filelist)
    else
        # Step through AST
        for i=1:length(expr.args)
            if typeof(expr.args[i]) == Expr
                find_function_in_ast_and_replace_return!(expr.args[i], fname, filelist)
            end
        end
    end
end


###################################################################################################
# Bcast

# Create batch resource for broadcasted variable
function create_bcast_batch_resource(blob_name, binary; container=nothing)

    # If bcast is overwrite of exisiting resources -> remove original one
    isnothing(container) && (container = __container__)
    for (client, resource) in zip(__clients__, __resources__)
        resource_idx = findall(x -> x.file_path == blob_name, resource)
        if ~isempty(resource_idx)
            popat!(resource, resource_idx[1]) # remove original resource
        end
        upload_bytes_to_container(client["blob_client"], container, blob_name, binary; verbose=__verbose__)
    end

    # Return future w/ blob name
    future = BatchFuture(container, BlobRef(blob_name))

    return future
end

# Broadcasting
function bcast_expression(expr::Symbol; container=nothing)

    filename = string(expr)
    isnothing(container) && (container = __container__)
    for client in __clients__
        create_blob_containers(client["blob_client"], [container]) # if not exist
    end

    # Return expression
    expr_out = quote
        _iobuff = IOBuffer()
        AzureClusterlessHPC.serialize(_iobuff, $expr)   # eval in local scope
        _binary = _iobuff.data

        # Create batch resource
        _blob_name = join([$filename, objectid($expr), ".dat"])
        create_bcast_batch_resource(_blob_name, _binary; container=$container)
    end
    return esc(expr_out)
end



###################################################################################################
# Macros

# Macro to upload stuff to batch
"""
    @batchdef expr

 Execute an expression under Main and on the batch workers of (future) batch jobs.

 *Usage*:

 - `@batchdef bar = 1` will define Main.bar on the current process and on all batch workers of
    batch jobs that are executed from the same session.

 
 See also: [`@batchexec`](@ref), [`batch_clear`](@ref) 
"""
macro batchdef(expr)

    # If expression is begin ... end block, split into single expressions
    if expr.head == :block
        for i=1:length(expr.args)
            if typeof(expr.args[i]) == Expr
                append_batchdef_expression(expr.args[i])
            end
        end
    else
        append_batchdef_expression(expr)
    end

    return esc(expr)    # esc makes expression available in caller scope
end


# Broadcasting: upload expr to blob and add to batch resource file
"""
    batch_future = @bcast expr

 Broadcast an expression to the workers of batch jobs that are executed from the current session. 
 `@bcast` uploades the tagged expression, creates a resource file for (future) batch jobs and returns 
 a `BatchFuture` of the expression.

 *Usage*:

 - `A = randn(2, 2); bfuture = @bcast A` will broadcast `A` to all batch workers/tasks of batch jobs that
    are executed from within the same session. 

 - The return argument is a `BatchFuture` that contains the name of the blob to which the expression was uploaded.
    To fetch the data associated with `batch_future`, use the `fetch` or `fetch!` function on it: `A = fetch(batch_future)`.
 
 See also: [`fetch`](@ref), [`fetch!`](@ref), [`@batchdef`](@ref), [`@batchexec`](@ref), [`batch_clear`](@ref) 
"""
macro bcast(expr)
    return bcast_expression(expr; container=nothing)
end

macro bcast(expr, container)
    return bcast_expression(expr; container=container)
end


# Run given expression as batch job
"""
    `batch_controller = @batchexec expr`

 Create a closure around an expression and run it automatically as a batch job, returning a future to the result. 
 If the expression is the `pmap` function, it is executed as a multi-task batch job.

 *Usage*:

 - `@batchexec print("Hello world")` executes the `print` function as a (single-task) batch job.

 - `@batchexec pmap(i -> print("Hello from \$i"), 1:10)` executes the `print` function as a multi-task batch job.

 - The return argument is a batch_controller that provides access to return arguments of the batch job,
    as well as basic job and pool functionalities. To fetch the output, use the `fetch` or `fetch!` function on
    it. These operations are blocking and wait for the completion of the batch job.
 
 See also:  [`BatchController`](@ref), [`fetch`](@ref), [`fetch!`](@ref), [`@batchdef`](@ref), [`batch_clear`](@ref)
 """
macro batchexec(expr)
    expr_out = create_expression_to_submit_batch_job(expr)
    return esc(expr_out)
end

macro batchexec(expr, options)
    expr_out = create_expression_to_submit_batch_job(expr; options=options)
    return esc(expr_out)
end
