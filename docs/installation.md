
# Installation and prerequisites

To install AzureClusterlessHPC.jl, run the following command from an interactive Julia session (press the `]` key and then type the command). When prompted, enter the user name and password that were provided to you:

```
] add https://github.com/microsoft/AzureClusterlessHPC.jl
```

AzureClusterlessHPC requires the Azure software development kits (SDKs) for batch computing, blob storage and common functionalities. See [pyrequirements.txt]() for the full list of current requirements. To install the required packages, run

```
# Go to AzureClusterlessHPC directory
cd /path/to/AzureClusterlessHPC
pip3 install -r pyrequirements.txt
```