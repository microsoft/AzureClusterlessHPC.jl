
# Collect output

## Fetch output

Executing a function as a batch job via `@batchexec` returns a batch controller of type `BatchController`:

```
# Test function
@batchdef function hello_world(n)
    A = zeros(n, n)
    B = ones(n, n)
    return A, B
end

# Execute function as a multi-task batch job
n = 2
batch_controller = @batchexec pmap(() -> hello_world(n), 1:2)  # 2 tasks
```

The batch controller has a field called `batch_controller.output`, which is a cell array of blob futures. The blob futures contain a (randomly generated) blob name of the future result stored in blob storage. E.g.:

```
julia> batch_controller.output

2-element Array{Any,1}:
 BlobFuture("redwoodtemp", BlobRef(("o9UspZStMmqn", "TwIMfLrYiac2")))
 BlobFuture("redwoodtemp", BlobRef(("PxgtEgZonWPJ", "kZz1Wuknnag0")))
```

The cell array contains one entry per task, i.e. `length(batch_controller.output)` is equal to the number of tasks of the executed batch job (in this case 2). As our function returns two arguments, each `BlobRef` contains two (future) blob names.

To fetch the output of an executed function, AzureClusterlessHPC provides the `fetch` and `fetch!` functions. These functions can be either called on the batch controller `output = fetch(batch_controller)` or they can be directly called on the blob futures:

```
# fetch called on batch controller
output_job = fetch(batch_controller)

# fetch called on blob future
output_task_1 = fetch(batch_controller.output[1])
```

However, we recommend to always call `fetch` on the batch controller and not on the batch futures in `.output`. Calling `fetch(batch_controller)` is a blocking operation and waits for all batch tasks to terminate. Calling `fetch(batch_controller.output[1])` is non-blocking and throws an exception if the task or job has not yet finished and the output is not yet available in blob storage.

AzureClusterlessHPC also supplies in-place fetch functions, which not only return the output, but they also overwrite the `BlobRef` of the `BlobFuture` in `batch_controller.output`:

```
# Inplace fetch
output = fetch!(batch_controller)

2-element Array{Any,1}:
 ([0.0 0.0; 0.0 0.0], [1.0 1.0; 1.0 1.0])
 ([0.0 0.0; 0.0 0.0], [1.0 1.0; 1.0 1.0])

batch_controller.output

2-element Array{Any,1}:
 BlobFuture("redwoodtemp", ([0.0 0.0; 0.0 0.0], [1.0 1.0; 1.0 1.0]))
 BlobFuture("redwoodtemp", ([0.0 0.0; 0.0 0.0], [1.0 1.0; 1.0 1.0]))
```

Inplace `fetch!` by default deletes the referenced blob objects. If `fetch!` is called on the batch controller again, it will then throw an error. To avoid deleting the blob, call `fetch!(batch_controller; destroy_blob=false)`. 


## Fetch output and apply reduction operation

AzureClusterlessHPC supplies the `fetchreduce` and `fetchreduce!` functions to collect the output from multiple tasks and apply a specified reduction operation to the output.
E.g. using the prior example:

```
# Test function
@batchdef function hello_world(n)
    A = ones(n, n)
    B = 2 .* ones(n, n)
    return A, B
end

# Execute function as a multi-task batch job
n = 2
batch_controller = @batchexec pmap(() -> hello_world(n), 1:2)  # 2 tasks
```

We can fetch and sum the output via:

```
output_sum = fetchreduce(batch_controller; op=+, remote=false)

# Returns
([2.0 2.0; 2.0 2.0], [4.0 4.0; 4.0 4.0])
```

The `remote` keyword argument specifies where the summation is execute. By default, the output is collected and summed on the master. For `remote=true`, AzureClusterlessHPC will schedule the summation tasks on idle instances in the batch pool and only the final (reduced) argument is copied back to the master.

We can also initialize the output ourselves and then call the in-place `fetchreduce!` function:

```
# Initialize output
output = (zeros(2, 2), zeros(2, 2))

# Fetch output and sum
fetchreduce!(batch_controller, output; op=+)

@show output
output = ([2.0 2.0; 2.0 2.0], [4.0 4.0; 4.0 4.0])
```
