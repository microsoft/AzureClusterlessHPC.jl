# Remote function calls

## @batchdef

Execute an expression under Main and on the batch workers of a (future) batch job that is executed from the same Julia session (equivalent to `@everywhere` for parallel Julia sessions).

```
@batchdef expr
```

`@batchdef` can be used to define variables, functions or with `include` and `using` statements:

```
# Import packages
@batchdef using LinearAlgebra, Random

# Includes
@batchdef include("testfile.jl")

# Define variables
@batchdef A = ones(2, 2)

# Define functions
@batchdef hello_world(name) = print("Hello $name")
```

You can define multiple expression with `@batchdef` using a `begin ... end` block:

```
@batchdef begin
    A = ones(1, 1)
    B = zeros(1, 1)
end
```

Expressions that are tagged via `@batchdef` are collected by AzureClusterlessHPC and are used in subsequent batch job executions. To print the current collection of expressions, type `batch_show()`. To reset the batch environment and remove all prior expressions from the call stack, use `batch_clear()` (or restart the Julia session).

## @batchexec

Execute an expression as a batch job (equivalent to `@spawn` for parallel Julia sessions).

```
@batchexec expr
```

The primary purpose of `@batchexec` is to execute functions that have been priorly defined with `@batchdef`. E.g.

```
# Define function
@batchdef function hello_world(name)
    print("Hello $name")
    return "Goodbye"
end

# Call function via batch
bctrl = @batchexec hello_world("Bob")
```

Arguments for functions executed via `@batchexec` are always **passed by copy**. This is important to keep in mind when passing large arguments to a function that is executed as a multi-task batch job, in which case arguments are copied to each task separately. To pass large arguments to a multi-task batch job, use the `@bcast` macro (see next section).


To execute a multi-task batch job, use the `pmap` function:

```
# Multi-task batch job
bctrl = @batchexec pmap(name -> hello_world(name), ["Bob", "Jane"])
```

The `@batchexec` macro returns a batch controller (`bctrl`) that can be used for the following actions:

- Wait for all tasks of the batch job to finish: `wait_for_tasks_to_complete(bctrl)`

- Terminate the batch job: `terminate_job(bctrl)`

- Delete the batch job: `delete_job(bctrl)`

- Delete the pool: `delete_pool(bctrl)`

- Delete the blob container in which all temporary files are stored: `delete_container(bctrl)`

- Destroy all Azure resources associated with the batch controller (job, pool, container): `destroy!(bctrl)`

- Fetch the output of all tasks: `output = fetch(bctrl)`. This operation is blocking and waits for all tasks to finish. The output is collected asynchonously in order of completion.

- Fetch the output of task `i`: `output = fetch(bctrl, i)` (blocking for that task).

- Inplace fetch (all tasks). Returns output and overwrites the blob future in `bctrl.output`: `output = fetch!(bctrl)` (blocking operation)

- Inplace fetch (task `i`): `output = fetch!(bctrl, i)` (blocking for task `i`)

- Fetch output of all tasks and apply a reduction operation to the output (along tasks): `output_reduce = fetchreduce(bctrl; op=+)` (blocking)

- Inplace fetch and reduce (overwrite `output_reduce`): `fetchreduce!(bctrl, output_reduce; op=+)` (blocking)


**Limitations:**

- Function return arguments must be explicitley returned via the `return` statement. I.e., implicit returns in which the final function expression is automatically returned are not supported.

- Functions executed via `@batchexec` can only have a single `return` argument. I.e. control structures such as `if ... else ... end` with multiple `return` statements are not supported and will throw an exception when fetching the output.

- Function arguments are passed by copy, never by reference.


## MPI support

You can execute tasks via Julia MPI on either single VMs or on multiple VMs. To enable MPI on a single VM (shared memory parallelism), set the following variables in your `parameters.json` file:

```
    "_INTER_NODE_CONNECTION": "0",
    "_MPI_RUN": "1",
    "_NUM_NODES_PER_TASK": "1",
    "_NUM_PROCS_PER_NODE": "2",
    "_OMP_NUM_THREADS": "1"
```

Note, that `"_NUM_NODES_PER_TASK"` must be set to `1` if `"_INTER_NODE_CONNECTION"` is set to `"0"`. `"_NUM_PROCS_PER_NODE"` specifies the number of MPI ranks per node and `"_OMP_NUM_THREADS"` specifies the number of OpenMP threads per rank (if applicable).

To enable MPI tasks on multiple instances (distributed memory parallelism), set:

```
    "_INTER_NODE_CONNECTION": "1",
    "_MPI_RUN": "1",
    "_NUM_NODES_PER_TASK": "2",
    "_NUM_PROCS_PER_NODE": "4",
    "_OMP_NUM_THREADS": "1"
```

The total number of MPI ranks for each task is given by `"_NUM_NODES_PER_TASK"` times `"_NUM_PROCS_PER_NODE"`. E.g. in this example, each MPI task is executed on 2 nodes with 4 processes per node, i.e. 8 MPI ranks in total.

In your application, you need to load the Julia MPI package via `@batchdef`. For a full MPI example, see `AzureClusterlessHPC/examples/mpi/julia_batch_mpi.ipynb`.

