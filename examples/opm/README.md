# Simulate CO2 Flow with Open Porous Media

This directory shows how run the Open Porous Media simulator (OPM) with Redwood for simulating training data to train data-driven CO2 flow simulators. The dataset in this example is based on the Sleipner reservoir simulation benchmark from [CO2 DataShare](https://co2datashare.org/dataset/sleipner-2019-benchmark-model).

This dataset is introduced in the paper pre-print ["Fast Co2 Flow Simulations on Large-Scale Geomodels with Artificial Intelligence-Based Wavelet Neural Operators"](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4207851). See the link for additional details.

If you want to use the dataset for training, you can directly download the (pre-)simulated version. See section "Pytorch data loader" for how to access the data.

## Generate training data for AI-driven CO2 flow

Running this example requires a docker image with OPM and the Redwood runtime. You can either build a new image from scratch as described in the following section or use the pre-built image from my public docker repository.

### Build docker image (optional)

To build the docker image from scratch, run:

```
# Build docker container
docker build -f docker/Dockerfile -t sleipnerwno:v1.0 .
```

Next, upload the image to your personal docker repository (or Azure Container registry):

```
# Upload to your personal docker repo
docker tag sleipnerwno:v1.0 mydockeraccount/sleipnerwno:v1.0
docker push mydockeraccount/sleipnerwno:v1.0
```

If you use your own docker image, update the image name in `parameters.json` accordingly.


### Run data generation

Start the data generation via:

```
julia run_opm_batch.jl
```

Note that the default setup creates a pool with 32 VMs and simulates 32 training examples only. To (re-)generate the full dataset, set the number of simulated samples to 4000 (line 112 in `run_opm_batch.jl`). The average task runtime is around 6 hours.


## Pytorch data loader

The dataset from the above paper reference is available for (free) download. The dataset consists of 4,000 training pairs, with input (permeability and topography) and output data (saturation, pressure). 

For accessing and downloading the data we provide a Pytorch dataloader. The data loader automatically downloads the samples from a public Azure storage container. See [load_training_data.ipynb]() for an example.


## Copyright

Copyright (c) Microsoft Corporation. All rights reserved.
Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.



