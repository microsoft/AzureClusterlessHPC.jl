#!/bin/bash

###################################################################################################
# DO NOT MODIFY!

# Switch to superuser and load module
sudo bash
pwd

# Install Julia
wget "https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.1-linux-x86_64.tar.gz"
tar -xvzf julia-1.6.1-linux-x86_64.tar.gz
rm -rf julia-1.6.1-linux-x86_64.tar.gz
ln -s /mnt/batch/tasks/startup/wd/julia-1.6.1/bin/julia /usr/local/bin/julia

# AzureClusterlessHPC
julia -e 'using Pkg; Pkg.add(url="https://github.com/microsoft/AzureClusterlessHPC.jl")'

# PyCall and Julia MPI
julia -e 'using Pkg; Pkg.add.(["PyCall", "MPI"])'
julia -e 'using PyCall'
julia --project -e 'ENV["JULIA_MPI_BINARY"]="system"; using Pkg; Pkg.build("MPI"; verbose=true)'
julia -e 'using MPI; MPI.install_mpiexecjl()'

###################################################################################################
# ADD USER PACKAGES HERE

# Install COFII
julia -e 'using Pkg; Pkg.add.([ "Distributed", "DistributedOperations", "Schedulers"])'

# Pre-compile packages
julia -e 'using Distributed, DistributedOperations, Schedulers'

###################################################################################################
# DO NOT MODIFY!

# Make julia dir available for all users
chmod -R 777 /mnt/batch/tasks/startup/wd/.julia
