
# Broadcasting

Broadcast an expression to all batch workers of (future) batch jobs and return a batch future. The batch future can be passed as a function argument instead of the variable.

```
batch_future = @bcast expr
```

The use of `@bcast` is recommended to pass large arguments to functions (e.g. arrays). This avoids copying input arguments to each individual task separately. Instead, expressions tagged via `@batchdef` are uploaded to blob storage once and their blob reference is passed to one or multiple tasks.

To access a broadcasted variable inside an executed function, use the `fetch` or `fetch!` (in-place) function:

```
# Create and broadcast array
A = randn(2, 2)
_A = @bcast A

# Define function
@batchdef function print_array(_A)
    A = fetch(_A)   # load A into memory
    print(A)
end

# Remotely execute function
@batchexec print_array(_A)  # pass batch future
```

Calling `A = fetch(_A)` on the local machine (rather than on a batch worker) downloads the broadcasted variable from blob storage and returns it.

