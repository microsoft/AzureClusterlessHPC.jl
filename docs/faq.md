# FAQ

- How does AzureClusterlessHPC work?

Whenever you tag an expression with `@batchdef`, AzureClusterlessHPC collects the abstract syntax tree (AST) of the expressions and appends it to a global collection. You can print the currently collected AST via `batch_show()` and you can reset the collected expressions via `batch_clear()`. When you use `@batchexec`, AzureClusterlessHPC creates a closure around the executed expression and uploads it, along with the collected AST as a batch resource file. AzureClusterlessHPC also anayzes the executed funtion and replaces return statements with serializations, so that return arguments are written to the local disk of the batch worker and subsequently uploaded to blob storage, from where they can be collected via the `fetch`/`fetch!` functions.

- What costs does AzureClusterlessHPC incur?

AzureClusterlessHPC calls Azure Batch and Azure Blob Storage APIs. Costs incur for operations that write data to blob storage, download or store it (e.g. `@bcast`, `@batchexec`, `fetch`, `fetch!`). For batch jobs, costs incur for the requested VMs in the batch pool (regardless of whether jobs are currently running or not). 

- How do I clean up and shut down all services that invoke costs?

Costs are invoked by a batch pool made up of one or multiple VMs and by files stored in blob storage. To shut down the pool run `delete_pool` and to delete the blob container that contains any temporary files run `delete_container()`. These actions will delete the pool and blob container specified in your parameter JSON file (or the default ones created by AzureClusterlessHPC).


- How can I specify Julia packages to be installed on the batch worker nodes?

To specify Julia packages that are installed on the worker nodes, create a pool startup script and use the `create_pool_and_resource_file` function to launch the pool. Refer to the section "Create a batch pool" for details.

- How can I start a pool with a custom VM image?

To start a pool with a custom VM image, you need to first create a custom VM image and then upload it to the Azure shared image gallery. The image gallery will assign an image reference ID to the image (see [here](https://docs.microsoft.com/en-us/azure/batch/batch-custom-images) for details on how to create a shared image). When starting your batch pool, pass this ID to the pool startup function: `create_pool(image_resource_id="shared_image_id")`.

- What kind of input and return arguments are supported in functions executed via `@batchexec`?

AzureClusterlessHPC.jl supports any kind of input and return arguments, including custom data structures. Input and return arguments do not need to be JSON serializable. However, we recommend using the same Julia version on the batch workers as on your local machine or master VM. This avoids possible inconsistencies when serializing/deserializing arguments and expressions.


- Are MPI and multi-node batch tasks supported?

Yes, you can execute AzureClusterlessHPC tasks via Julia MPI on either single VMs or on multiple VMs. See the above section **MPI support** for details on how to runs batch tasks with MPI support.


