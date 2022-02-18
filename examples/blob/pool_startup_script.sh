#!/bin/bash

###################################################################################################
# DO NOT MODIFY!

# Switch to superuser and load module
sudo bash
pwd

# Install Julia
wget "https://julialang-s3.julialang.org/bin/linux/x64/1.7/julia-1.7.2-linux-x86_64.tar.gz"
tar -xvzf julia-1.7.2-linux-x86_64.tar.gz
rm -rf julia-1.7.2-linux-x86_64.tar.gz
ln -s /mnt/batch/tasks/startup/wd/julia-1.7.2/bin/julia /usr/local/bin/julia

# AzureClusterlessHPC
julia -e 'using Pkg; Pkg.add(url="https://github.com/microsoft/AzureClusterlessHPC.jl")'

# PyCall
julia -e 'using Pkg; Pkg.add.(["PyCall"])'
julia -e 'using PyCall'


###################################################################################################
# ADD USER PACKAGES HERE

# ...


###################################################################################################
# DO NOT MODIFY!

# Install Azure Python SDKs
apt update -y
apt install python3-pip -y
pip3 install --user azure-batch==9.0.0 azure-common azure-storage-blob==1.3.1 azure-storage-queue==1.4.0

# Make julia dir available for all users
chmod -R 777 /mnt/batch/tasks/startup/wd/.julia
chmod -R 777 /mnt/batch/tasks/startup/wd/.local
