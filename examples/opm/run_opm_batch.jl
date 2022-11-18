#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------


#######################################################################################################################
# Batch pool

ENV["PARAMETERS"] = joinpath(pwd(), "parameters.json")
ENV["CREDENTIALS"] = joinpath(pwd(), "credentials.json")

using AzureClusterlessHPC, PyCall, HDF5, PyPlot
batch_clear()

# Create pool
create_pool()


#######################################################################################################################
# Run OPM

# Load packages
@batchdef using PyCall, Random

# Include files
@batchdef begin
    fileinclude("SLEIPNER_ORG.DATA")
    fileinclude("SCHEDULE.INC")
    fileinclude("gen_model_sleipner.py")
    fileinclude("sleipner_tops_orig.h5")
end

# Include current path in Python environment
@batchdef pushfirst!(PyVector(pyimport("sys")."path"), pwd())

# Run OPM
@batchdef function run_opm(isim, filename, shape, nbpml, sx, sy, sz1, sz2, opm_cmd, url, container, credential)

    # Zarr client
    blob = pyimport("azure.storage.blob")
    client = blob.ContainerClient(
        account_url=url,
        container_name=container,
        credential=credential
    )

    # Run model generation script
    model_generator = pyimport("gen_model_sleipner")
    well = zeros(shape)
    well[sx, sy, :] .= 1
    permxy, permz, poro, tops = model_generator.gen_sleipner(shape..., nbpml, sx, sy, sz1, sz2)[1:4]

    # Run OPM
    ENV["OMP_NUM_THREADS"] = 4
    run(opm_cmd)

    # Read grid
    grid = pyimport("ecl.grid")
    ecl = pyimport("ecl.eclfile")
    grid = grid.EclGrid(join([filename, ".EGRID"]))

    # Read snapshots & models
    rst_file = ecl.EclRestartFile(grid, join([filename, ".UNRST"]))

    # Read pressure & saturation
    nt = length(get(rst_file, "PRESSURE"))
    pressure = zeros(Float32, (nt, shape...))
    saturation = zeros(Float32, (nt, shape...))
    for j=1:nt
        pressure[j, :, :, :] = reshape(get(rst_file, "PRESSURE")[j].numpy_view(), shape .+ 2*nbpml)[nbpml+1:end-nbpml, nbpml+1:end-nbpml, nbpml+1:end-nbpml]
        saturation[j, :, :, :] = reshape(get(rst_file, "SGAS")[j].numpy_view(), shape .+ 2*nbpml)[nbpml+1:end-nbpml, nbpml+1:end-nbpml, nbpml+1:end-nbpml]
    end

    # Remove padding
    permxy = permxy[nbpml+1:end-nbpml, nbpml+1:end-nbpml, nbpml+1:end-nbpml]
    permz = permz[nbpml+1:end-nbpml, nbpml+1:end-nbpml, nbpml+1:end-nbpml]
    tops = tops[nbpml+1:end-nbpml, nbpml+1:end-nbpml]

    # Reshuffle dimensions to (Z Y X T)
    permxy = permutedims(permxy, (3,2,1))
    permz = permutedims(permz, (3,2,1))
    well = permutedims(well, (3,2,1))
    tops = permutedims(tops, (2,1))
    pressure = permutedims(pressure, (4,3,2,1))[:,:,:,1:4:end]
    saturation = permutedims(saturation, (4,3,2,1))[:,:,:,1:4:end]

    # Write results to blob
    zarr = pyimport("zarr")
    store = zarr.ABSStore(container=container, prefix="dataset", client=client)  
    root = zarr.group(store=store, overwrite=false)
    root.array("permxy_" * string(isim), permxy, chunks=(32, 32, 32), overwrite=true)
    root.array("permz_" * string(isim), permz, chunks=(32, 32, 32), overwrite=true)
    root.array("well_" * string(isim), well, chunks=(32, 32, 32), overwrite=true)
    root.array("tops_" * string(isim), tops, chunks=(32, 32), overwrite=true)
    root.array("pressure_" * string(isim), pressure, chunks=(31, 32, 32, 32), overwrite=true)
    root.array("saturation_" * string(isim), saturation, chunks=(31, 32, 32, 32), overwrite=true)
end


#######################################################################################################################

# Required arguments
filename = "SLEIPNER_ORG"
shape = (60, 60, 64)    # nx, ny, nz
nbpml = 0
sx = 30
sy = 30
sz1 = 60
sz2 = 60
opm_cmd = `flow $filename.DATA`
ntrain = 4000

url = "https://mystorageaccount.blob.core.windows.net"
container = "mycontainer"
credential = "mykey"

bctrl = @batchexec pmap(isim -> run_opm(isim, filename, shape, nbpml, sx, sy, sz1, sz2, opm_cmd, url, container, credential), 1:ntrain)
wait_for_tasks_to_complete(bctrl; timeout=999, task_timeout=999, num_restart=4)

# Delete resources
destroy!(bctrl)