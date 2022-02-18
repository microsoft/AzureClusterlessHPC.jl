FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive 

# Set up base and ssh keys
COPY ssh_config /root/.ssh/config

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates wget openssh-client openssh-server \
        mpich libmpich-dev \
    && mkdir -p /var/run/sshd \
    && ssh-keygen -A \
    && sed -i 's/UsePAM yes/UsePAM no/g' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/g' /etc/ssh/sshd_config \
    && sed -i 's/#RSAAuthentication yes/RSAAuthentication yes/g' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config \
    && ssh-keygen -f /root/.ssh/id_rsa -t rsa -N '' \
    && chmod 600 /root/.ssh/config \
    && chmod 700 /root/.ssh \
    && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# Required application packages
RUN apt-get install -y gfortran python3-pip && \
    apt-get install -y git wget vim htop hdf5-tools

# Install Azure Python SDKs
RUN pip3 install azure-batch==9.0.0 azure-common azure-storage-blob==1.3.1 azure-storage-queue==1.4.0

# Install Julia
RUN wget "https://julialang-s3.julialang.org/bin/linux/x64/1.7/julia-1.7.2-linux-x86_64.tar.gz" && \
    tar -xvzf julia-1.7.2-linux-x86_64.tar.gz && \
    rm -rf julia-1.7.2-linux-x86_64.tar.gz && \
    ln -s /julia-1.7.2/bin/julia /usr/local/bin/julia

# AzureClusterlessHPC
RUN julia -e 'using Pkg; Pkg.add.(["PyCall"])' && \
    julia -e 'using Pkg; Pkg.add(url="https://github.com/microsoft/AzureClusterlessHPC.jl")' && \
    julia -e 'using PyCall; using AzureClusterlessHPC'

RUN chmod -R 777 /root/.julia

# clean
RUN rm -rf /var/lib/apt/lists/* \
	&& apt-get clean