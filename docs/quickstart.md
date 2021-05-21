# Quick start

To run this example, you need to have followed the installation and setup steps in [Installation](https://microsoft.github.io/AzureClusterlessHPC.jl/installation/). Complete the steps in the installation section before proceeding. See section [Credentials](https://microsoft.github.io/AzureClusterlessHPC.jl/credentials/) for additional information on resources and credentials.

To run our first example, we move to the `/examples/batch` directory and have a look at the directory content:

```
# Go to example directory
cd /path/to/AzureClusterlessHPC/examples/batch

# List directory content
ls -l

julia_batch_macros.ipynb
parameters.json
pool_startup_script.sh
```

We can see that our directory contains a `parameters.json` file with job parameters such as the number and type of Azure instances for our pool. (See section [User parameters](https://microsoft.github.io/AzureClusterlessHPC.jl/credentials/#user-parameters) for a list of all available job parameters.) Additionally, we have a `pool_startup_script.sh` that is executed by every new VM joining a pool and which allows us to specify dependiencies that need to be installed on the worker nodes. Alternatively, we can also start pools with a managed VM image or using [Docker images](https://github.com/microsoft/AzureClusterlessHPC.jl/blob/main/examples/container/julia_batch_docker.ipynb).


Next, we start a Julia session and set the environment variables `CREDENTIALS` and `PARAMETERS` so that they point to your parameter and credential file. You can either set the variables in your bash terminal (e.g. in your `~/.bashrc` file), or directly in the Julia terminal:

```
# Set path to credentials in Julia
ENV["CREDENTIALS"] = joinpath(pwd(), "credentials.json")

# Set path to batch parameters (pool id, VM types, etc.)
ENV["PARAMETERS"] = joinpath(pwd(), "parameters.json")
```

Next, load AzureClusterlessHPC.jl and create a pool with the parameters from `parameters.json` and using our `pool_startup_script.sh`:

```
# Load package
using AzureClusterlessHPC

# Create default pool with parameters from parameters.json
startup_script = "pool_startup_script.sh"
create_pool_and_resource_file(startup_script)
```

You can check the status of your batch pool in the [Microsoft Azure Portal](https://azure.microsoft.com/en-us/features/azure-portal/) or with the [Azure Batch Explorer](https://azure.github.io/BatchExplorer/) (recommended). 

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