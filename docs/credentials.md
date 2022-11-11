# Parameters and credentials 


## Single batch and storage account

`AzureClusterlessHPC.jl` requires at the minimum **one Azure Batch** account and **one Azure Storage** account. The storage account is authenticated via a secret key, whereas Azure Batch must be authenticated using the Azure Active Directory (AAD). The `setup.sh` script in the root directory automatically creates the accounts and creates a `credentials.json` file. 

Alternatively, you can set up the accounts manually (e.g. using the Azure console). Refer to the [Azure documentation](https://docs.microsoft.com/en-us/azure/batch/batch-aad-auth) for information on how to authenticate Azure Batch via the AAD. Once you have created the accounts, create a credential file with the storage key and batch AAD authentication. Use the following template for the `credentials.json` file: 

```
{
    "_AD_TENANT": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",

    "_AD_BATCH_CLIENT_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "_AD_SECRET_BATCH": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "_BATCH_ACCOUNT_URL": "https://batchaccountname.batchregion.batch.azure.com",
    "_BATCH_RESOURCE": "https://batch.core.windows.net/",
    
    "_STORAGE_ACCOUNT_NAME": "storageaccountname",
    "_STORAGE_ACCOUNT_KEY": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

When using AzureClusterlessHPC, set the environment variable `ENV["CREDENTIALS"] = "/path/to/credentials.json"` **before** you load the package via `using AzureClusterlessHPC`.


## Job monitoring via App Insights

`AzureClusterlessHPC.jl` supports job monitoring via Azure Batch Insights. Follow [the Batch Insights instructions](https://github.com/Azure/batch-insights) to set up Applications insights in the Azure portal. From your application, retrieve the app insights ID and the instrumentation key and add them to your `credentials.json` file: 

```
{
    "_APP_INSIGHTS_APP_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "_APP_INSIGHTS_INSTRUMENTATION_KEY": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

## Multi accounts

AzureClusterlessHPC also allows using multiple storage and/or batch accounts. Using multiple batch accounts provides the possiblity to cirumvent service limits of a single batch account or it allows to distribute workloads among multiple regions. If you create batch accounts for multiple regions, you need to have at least one storage account in each region. To automatically create multiple batch and storage accounts, use the shell script `create_azure_accounts.sh`. Pass the list of region(s) and the number of accounts per region as command line arguments to the script. E.g., to create two batch and storeage acounts in each US West and South Central US (i.e, total of 4 batch and 4 storage accounts), run:

```
# Go to AzureClusterlessHPC directory
cd /path/to/AzureClusterlessHPC

# Azure CLI log in
az login

# Create accounts
./create_azure_accounts "westus southcentralus" 2
```

Creating the accounts may take several minutes, depending on how many accounts are being created. The script also fetches the required credentials and stores them in the directory `user_data`. No further actions from the user side are required. To use the credentials stored in `user_data` with AzureClusterlessHPC, make sure that the environment variable `"CREDENTIALS"` is unset (run `unset CREDENTIALS` from the bash command line). If `CREDENTIALS` is not set, AzureClusterlessHPC will automatically look for credentials in `user_data`. 

After loading AzureClusterlessHPC in Julia (`using AzureClusterlessHPC`), you can check which accounts were found by checking `AzureClusterlessHPC.__credentials__`. This returns a list with one entry per available batch account. Type `AzureClusterlessHPC.__credentials__[i]` to print the credential information for the `i-th` account.


## User parameters

Users can optionally provide a `parameters.json` file that specifies pool and job parameters. Set the environment variable `ENV["PARAMETERS"]=/path/to/parameters.json` **before** loading the package (see section "Quickstart" for an example).

The following set of parameters and default values are used, unless specified otherwise by the user:

```
{    
    "_POOL_ID": "BatchPool",
    "_POOL_COUNT": "1",
    "_NODE_COUNT_PER_POOL": "1",
    "_POOL_VM_SIZE": "Standard_E2s_v3",
    "_JOB_ID": "BatchJob",
    "_STANDARD_OUT_FILE_NAME": "stdout.txt",
    "_NODE_OS_PUBLISHER": "Canonical",
    "_NODE_OS_OFFER": "UbuntuServer",
    "_NODE_OS_SKU": "18.04",
    "_BLOB_CONTAINER": "redwoodtemp",
    "_INTER_NODE_CONNECTION": "0",
    "_NUM_RETRYS": "0",
    "_MPI_RUN": "0",
    "_CONTAINER": "None",
    "_NUM_NODES_PER_TASK": "1",
    "_NUM_PROCS_PER_NODE": "1",
    "_OMP_NUM_THREADS": "1",
    "_JULIA_DEPOT_PATH": "/mnt/batch/tasks/startup/wd/.julia",
    "_PYTHONPATH": "/mnt/batch/tasks/startup/wd/.local/lib/python3.6/site-packages"
}
```

**Note:** Do not modify the `"_JULIA_DEPOT_PATH"` and `"_PYTHONPATH"` unless you use a pool with a custom image or Docker container in which Julia has been already installed. In that case, set the depot path to the location of the `.julia` directory.

