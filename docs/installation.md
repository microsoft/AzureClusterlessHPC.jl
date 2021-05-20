# Installation and setup

Using `AzureClusterlessHPC` requires at the minimum one Azure Batch and one Azure Blob Storage account. Before being able to run the example, follow the instructions from this section to install the package and dependencies, and set up the necessary Azure resources.

## Install Julia package

Run the following command from an interactive Julia session to install `AzureClusterlessHPC.jl` (press the `]` key and then type the command)

```
] add https://github.com/microsoft/AzureClusterlessHPC.jl
```


## Install Python dependencies

AzureClusterlessHPC requires the Azure software development kits (SDKs) for batch computing, blob storage and common functionalities. Install the required packages via:

```
# Go to AzureClusterlessHPC directory
cd /path/to/AzureClusterlessHPC
pip3 install -r pyrequirements.txt
```

Next, we need to make sure that Julia is pointed to the correct Python version in which we installed our packages. Run `which python3` from the terminal and then start a Julia session and run (replace `/path/to/python3` with the correct path):

```
using Pkg, PyCall

ENV["PYTHON"] = "/path/to/python3"
Pkg.build("PyCall")
```

## Create Azure Storage and Batch account

Follow the following steps to create and Azure Storage and Batch account See [here](https://docs.microsoft.com/en-us/cli/azure/) for installation instructions. 

First, log into Azure by running from the terminal:

```
az login
```

Next, we s

```
# Set region (e.g. US South Central)
REGION="southcentralus"
```



```
# Get tenant id
SUBSCRIPTION_ID=`az account show --query id --output tsv`

# Create resource group
az group create --name redwood-rg-${REGION} --location ${REGION}

# Create storage account
az storage account create --name redstore${REGION}${i} --location ${REGION} --resource-group redwood-rg-${REGION} --sku Standard_LRS

# Create batch account
az batch account create --name redbatch${REGION}${i} --location ${REGION} --resource-group redwood-rg-${REGION} --storage-account redstore${REGION}${i}

# Register batch app
APP_ID=`az ad app create --display-name redbatch${REGION}${i} | jq  -r '.appId'`

# Create service principal
az ad sp create --id $APP_ID

# Assign RBAC to application
        az role assignment create --assignee $APP_ID --role "Contributor" --scope \
        "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/redwood-rg-${REGION}/providers/Microsoft.Batch/batchAccounts/redbatch${REGION}${i}"
```


## Set up credentials



## Test setup

Start a Julia session and set the `CREDENTIALS` environment variable so that it points to your credential file:

```
# Set path to credential file
ENV["CREDENTIALS"] = "/path/to/credentials.json"

# Load package
using AzureClusterlessHPC
```

If you were able to load the package without any warnings or erros, you're good to go. Proceed to the [Quickstart](https://microsoft.github.io/AzureClusterlessHPC.jl/quickstart/) section in the documentation or browse through the [example notebooks](https://github.com/microsoft/AzureClusterlessHPC.jl/tree/main/examples).