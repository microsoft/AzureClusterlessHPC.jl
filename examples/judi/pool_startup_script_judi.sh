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

# Install AzureClusterlessHPC
julia -e 'using Pkg; Pkg.add(url="https://github.com/microsoft/AzureClusterlessHPC.jl")'

###################################################################################################
# ADD USER PACKAGES HERE

# Install devito
apt update
apt install -y python3-pip
pip3 install devito

# Install Julia packages
julia -e 'using Pkg; Pkg.develop(PackageSpec(url="https://github.com/slimgroup/SegyIO.jl"))'
julia -e 'using Pkg; Pkg.develop(PackageSpec(url="https://github.com/slimgroup/JOLI.jl"))'
julia -e 'using Pkg; Pkg.develop(PackageSpec(url="https://github.com/slimgroup/JUDI.jl"))'
julia -e 'using Pkg; Pkg.add("HDF5"); Pkg.add("PyPlot")'    
julia -e 'using JUDI.TimeModeling, SegyIO'
julia -e 'using Pkg; ENV["PYTHON"]="/usr/bin/python3"; Pkg.build("PyCall")'

###################################################################################################
# DO NOT MODIFY!

# Make julia dir available for all users
chmod -R 777 /mnt/batch/tasks/startup/wd/.julia
