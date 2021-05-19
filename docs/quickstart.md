# Quick start

Before running an example, we need to create two JSON files with our Azure credentials and the job parameters, as well as a bash startup-script for the worker nodes. Templates for these files are located in the examples directory:

```
# Go to example directory
cd /path/to/AzureClusterlessHPC/examples/batch

# List directory content
ls -l

credentials.json
julia_batch_macros.ipynb
parameters.json
pool_startup_script.sh
```

Fill out the missing information in `credentials.json` and in `parameters.json` (see the next section "Parmeters and credentials" for additional information). Then set the environment variables `CREDENTIALS` and `PARAMETERS` so that they point to the files. You can either set the variables in your bash terminal (e.g. in your `~/.bashrc` file), or directly in the Julia terminal:

```
# Set path to credentials in Julia
ENV["CREDENTIALS"] = joinpath(pwd(), "credentials.json")

# Set path to batch parameters (pool id, VM types, etc.)
ENV["PARAMETERS"] = joinpath(pwd(), "parameters.json")
```

Next, load AzureClusterlessHPC.jl and create a pool with the parameters from `parameters.json`:

```
# Load package
using AzureClusterlessHPC

# Create default pool with parameters from parameters.json
startup_script = "pool_startup_script.sh"
create_pool_and_resource_file(startup_script)
```

Remark: If a pool with the name as specified in `parameter.json` already exists, the `create_pool_and_resource_file` function will throw an error.In practice, use a `try ... catch` block around this expression.

Now you can execute Julia functions that are defined using the `@batchdef` macro via Azure batch:

```
# Define function
@batchdef function hello_world(name)
    print("Hello $name")
    return "Goodbye"
end

# Execute function via Azure batch
@batchexec hello_world("Bob")
```

You can also run multi-tasks batch job using the `pmap` function in combination with `@batchdef`:

```
# Run a multi-task batch job
@batchexec pmap(name -> hello_world(name), ["Bob", "Jane"])
```

To delete all resources run:

```
# Shut down pool
delete_pool()

# Delete container with temporary blob files
delete_container()
```