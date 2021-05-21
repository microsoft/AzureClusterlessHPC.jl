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

Using `AzureClusterlessHPC.jl` requires an Azure Storage and Azure Batch account with AAD authentication. First, install the Azure Command Line Interface (CLI) by following the instructions [here](https://docs.microsoft.com/en-us/cli/azure/).

Next, log into your Azure account by running:

```
az login
```

Once you have sucessfully logged in, follow the next steps to create all required accounts and to create a credential file:

```
# Move to AzureClusterlessHPC directory
cd /path/to/AzureClusterlessHPC

# Create accounts for given base name
./setup myname
```

The shell script writes the credentials to `/path/to/AzureClusterlessHPC/credentials.json`. **Make sure to never check this credential file into git and keep it private!**


## Test setup

Start a Julia session and set the `CREDENTIALS` environment variable so that it points to your credential file:

```
# Set path to credential file
ENV["CREDENTIALS"] = "/path/to/AzureClusterlessHPC/credentials.json"

# Load package
using AzureClusterlessHPC
```

If you were able to load the package without any warnings or erros, you're good to go. Proceed to the [Quickstart](https://microsoft.github.io/AzureClusterlessHPC.jl/quickstart/) section in the documentation or browse through the [example notebooks](https://github.com/microsoft/AzureClusterlessHPC.jl/tree/main/examples).