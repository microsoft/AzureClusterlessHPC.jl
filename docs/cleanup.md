# Clean up resources


After executing a batch job via `@batchexec`, you can use the returned batch controller to clean up resources:

```
# Batch job
batch_controller = @batchexec print("Hello world")

# Terminate job
terminate_job(batch_controller)

# Delete job
delete_job(batch_controller)

# Delete pool
delete_pool(batch_controller)

# Delete blob container with all temporary files
delte_container(batch_controller)

# Or alternatively, delete pool + job + container together
destroy!(batch_controller)
```

If you did not return a batch controller, you can call the following functions without any input arguments, in which case they will delete the pool and container as specified in your `parameter.json` file (or the default ones). The `delete_all_jobs` function will delete all exisiting jobs that start with the job id specified in the parameter file.

```
# Delete container
delete_container()

# Delete pool
delete_pool()

# Delete all jobs
delete_all_jobs()
```