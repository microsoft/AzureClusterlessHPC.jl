# Managing pools

## Start a pool

To start a batch pool and (optionally) install a set of specified Julia packages on the workers, we first need to create a bash script of the following form, which will be executed by each node joining the pool:

```
#!/bin/bash

###################################################################################################
# DO NOT MODIFY!

# Switch to superuser and load module
sudo bash
pwd

# Install Julia
wget "https://julialang-s3.julialang.org/bin/linux/x64/1.5/julia-1.5.2-linux-x86_64.tar.gz"
tar -xvzf julia-1.5.2-linux-x86_64.tar.gz
rm -rf julia-1.5.2-linux-x86_64.tar.gz
ln -s /mnt/batch/tasks/startup/wd/julia-1.5.2/bin/julia /usr/local/bin/julia

# Install AzureClusterlessHPC
git clone https://github.com/microsoft/AzureClusterlessHPC.jl
julia -e 'using Pkg; Pkg.add(url=joinpath(pwd(), "AzureClusterlessHPC"))'

###################################################################################################
# ADD USER PACKAGES HERE
# ...

###################################################################################################
# DO NOT MODIFY!

# Make julia dir available for all users
chmod -R 777 /mnt/batch/tasks/startup/wd/.julia

```

If you need to install Julia packages for your application, specify the packages in the section `# ADD USER PACKAGES HERE`. E.g. to install the Julia package `IterativeSolvers.jl`, add the line:

```
julia -e 'using Pkg; Pkg.add("IterativeSolvers")'
```

To install packages that are not officially registered with Julia, use this line to add packages:

```
julia -e 'using Pkg; Pkg.develop(PackageSpec(url="https://github.com/slimgroup/JOLI.jl"))'
```

Save this batch script, e.g. as `pool_startup_script.sh`. You can now create a pool in which the startup script will be executed on each node that joins the pool:

```
# Path to bash file
startup_script = "/path/to/pool_startup_script.sh"

# Create pool
create_pool_and_resource_file(startup_script; enable_auto_scale=false, auto_scale_formula=nothing,
    auto_scale_evaluation_interval_minutes=nothing, image_resource_id=nothing)
```

**Required input arguments:**

- `startup_script`: String that defines the path and name of the bash startup script.


**Optional keyword arguments**:

- `enable_auto_scale=false`: Enable auto scaling. If `true`, the keyword arguments `auto_scale_formula` and `auto_scale_evaluation_interval_minutes` must be provided as well. If the parameter `_POOL_NODE_COUNT` has been set, it will be ignored.

- `auto_scale_formula=nothing`: String that defines the auto-scaling behavior. See [here](https://docs.microsoft.com/en-us/azure/batch/batch-automatic-scaling) for Azure Batch auto-scaling templates.

- `auto_scale_evaluation_interval_minutes=nothing`: Time interval between evaluations of the auto-scaling function. The minimum possible interval is 5 minutes.

- `image_resource_id=nothing`: Provide an optional image resource ID to use a custom machine image for nodes joining the batch pool.



## Pools with managed VM images

To launch a pool with a custom VM image, you need to create a custom VM image and then upload it to the Azure shared image gallery. The image gallery will assign an image reference ID to the image (see [here](https://docs.microsoft.com/en-us/azure/batch/batch-custom-images) for details on how to create a shared image).

Once you have the shared image ID, pass it as a keyword argument `image_resource_id` to the `create_pool` function. If you do not pass the image ID to the function, workers are created with the default Ubuntu image, which does not have Julia installed.

```
# Image resource ID
image_id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Create pool with custom VM image
create_pool(image_resource_id=image_id, enable_auto_scale=false, auto_scale_formula=nothing,
    auto_scale_evaluation_interval_minutes=nothing)
```

**Optional keyword arguments:**

- `image_resource_id=nothing`: Image resource ID to use a custom machine image for nodes joining the batch pool.

For a description of all other keyword arguments, see the above section.

**Important**: In your parameter file, set the variable `"_JULIA_DEPOT_PATH"` to the path where Julia is installed on the image.


## Pools with Docker

As a third alternative, you can create an application package using Docker. You first create or specify a Docker image, which will then be pre-installed on each VM joining the batch pool. See the example directory `/path/to/redwood/examples/container` for an example Dockerfile. Follow the subsequent instructions to create a Docker image from a Dockerfile and upload it to your (personal) container repository:

```
# Move to directory with Dockerfile
cd /path/to/redwood/examples/container

# Build image
docker build -t redoowd:v1.0 .

# Login
docker login

# Tag and push
docker tag redwood:v1.0 username/redwood:v1.0
docker push username/redwood:v1.0
```

Once you have a Docker image in a public repository, you can specify a Docker image in your `parameters.json` file:

```
    "_CONTAINER": "username/redwood:v1.0"
```

If the `_CONTAINER` parameter is set, AzureClusterlessHPC will install the specified container image on the VMs in the batch pool.


## Pool autoscaling

To create a pool with auto-scaling, use one of the above commands and set the following keyword arguments:

- Set the keyword argument `enable_auto_scale=true`

- Define an auto-scaling formula. E.g. the following formula creates a pool with 1 node and resizes the pool to up to 10 VMs based on the number of pending tasks:

```
auto_scale_formula = """startingNumberOfVMs = 1;
    maxNumberofVMs = 10;
    pendingTaskSamplePercent = \$PendingTasks.GetSamplePercent(30 * TimeInterval_Second);
    pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNumberOfVMs : avg(\$PendingTasks.GetSample(30 * TimeInterval_Second));
    \$TargetDedicatedNodes=min(maxNumberofVMs, pendingTaskSamples);
    \$NodeDeallocationOption = taskcompletion;"""
```

For other auto-scaling formulas, refer to the [Azure Batch documentation](https://docs.microsoft.com/en-us/azure/batch/batch-automatic-scaling).

- Set the auto-scaling interval: `auto_scale_evaluation_interval_minutes=5`. The minimum allowed values is 5 minutes.

The full example would look like this:

```
# Pool startup script
startup_script = "/path/to/pool_startup_script.sh"

# Autoscale formula
auto_scale_formula = """startingNumberOfVMs = 1;
    maxNumberofVMs = 10;
    pendingTaskSamplePercent = \$PendingTasks.GetSamplePercent(30 * TimeInterval_Second);
    pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNumberOfVMs : avg(\$PendingTasks.GetSample(30 * TimeInterval_Second));
    \$TargetDedicatedNodes=min(maxNumberofVMs, pendingTaskSamples);
    \$NodeDeallocationOption = taskcompletion;"""

create_pool_and_resource_file(startup_script; enable_auto_scale=true, auto_scale_formula=auto_scale_formula,            
    auto_scale_evaluation_interval_minutes=5)
```


## Pool resize

Currently not supported.