# Installation and setup

Using `AzureClusterlessHPC` requires at the minimum one Azure Batch and one Azure Blob Storage account. Before being able to run the example, follow the instructions from this section to install the package and dependencies, and set up the necessary Azure resources.

## Prerequisites

- Ubuntu 18.04/20.04 or Debian 10

- Julia v1.5 or later

- Python3 and pip3


## Install Julia package

Run the following command from an interactive Julia session to install `AzureClusterlessHPC.jl` (press the `]` key and then type the command)

```
] dev https://github.com/microsoft/AzureClusterlessHPC.jl
```


## Install Python dependencies

AzureClusterlessHPC requires the Azure software development kits (SDKs) for batch computing, blob storage and common functionalities. Install the required packages via:

```
# Go to AzureClusterlessHPC directory
cd ~/.julia/dev/AzureClusterlessHPC
pip3 install -r pyrequirements.txt
```

Next, we need to make sure that Julia is pointed to the correct Python version in which we installed our packages. Run `which python3` from the terminal and then start a Julia session and run (replace `/path/to/python3` with the correct path):

```
using Pkg, PyCall   # run Pkg.add("PyCall") is necessary

ENV["PYTHON"] = "/path/to/python3"
Pkg.build("PyCall")
```

## Create Azure Storage and Batch account

Using `AzureClusterlessHPC.jl` requires an Azure Storage and Azure Batch account with AAD authentication. First, install the Azure Command Line Interface (CLI) by running (see [here](https://docs.microsoft.com/en-us/cli/azure/) for additional instructions):

```
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Next, log into your Azure account:

```
az login
```

Once you have sucessfully logged in, follow the next steps to create all required accounts and to create a credential file:

```
# Move to AzureClusterlessHPC directory
cd ~/.julia/dev/AzureClusterlessHPC

# Install JSON parsing
sudo apt-get update -y & sudo apt-get install -y jq

# Create batch and storage accounts with given base name and region
./deploy myname southcentralus
```

The shell script writes the credentials to `/path/to/AzureClusterlessHPC/credentials.json`. **Make sure to never check this credential file into git and keep it private!**


## Test setup

Start a Julia session and set the `CREDENTIALS` environment variable so that it points to your credential file:

```
# Set path to credential file
using Pkg
ENV["CREDENTIALS"] = Pkg.dir("AzureClusterlessHPC", "credentials.json")

# Load package
using AzureClusterlessHPC
```

If you were able to load the package without any warnings or erros, you're good to go. Proceed to the [Quickstart](https://microsoft.github.io/AzureClusterlessHPC.jl/quickstart/) section in the documentation or browse through the [example notebooks](https://github.com/microsoft/AzureClusterlessHPC.jl/tree/main/examples).