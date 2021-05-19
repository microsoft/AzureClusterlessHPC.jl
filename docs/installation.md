
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


## Set up credentials



## Test setup

Start a Julia session and set the `CREDENTIALS` environment variable so that it points to your credential file:

```
# Set path to credential file
ENV["CREDENTIALS"] = "/path/to/credentials.json"

# Load package
using AzureClusterlessHPC
```

If you were able to load the package without any warnings or erros, you should be good to go. If you type `AzureClusterlessHPC.__credentials__`, you should see your credentials.

Once you have complete all steps successfully you can check out [this notebook]() to learn the basic of how to use `AzureClusterlessHPC`.