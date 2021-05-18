#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

export BlobRef, BlobFuture, BatchFuture, fetch, fetch!


###################################################################################################
# Blob reference: a string that describes a blob in blob storage

mutable struct BlobRef
    name::Union{String, Tuple}
end

###################################################################################################
# Batch Future: reference to batch resource on worker's disk (worker-side fetch)

mutable struct BatchFuture
    container::Union{String, Nothing}
    blob
end

BatchFuture(container) = BatchFuture(container, nothing)
BatchFuture() = BatchFuture(nothing, nothing)

# Fetch on a batch worker (if executed on user-side -> fetch data from blob)
function fetch(arg::BatchFuture)
    try
        iostream = open(arg.blob.name, "r")
        data = deserialize(iostream)
        close(iostream)
        return data
    catch
        iostream = __clients__[1]["blob_client"].get_blob_to_bytes(arg.container, arg.blob.name)
        return deserialize(IOBuffer(iostream.content))
    end
end

function fetch!(arg::BatchFuture)
    data = nothing
    try
        iostream = open(arg.blob.name, "r")
        data = deserialize(iostream)
        close(iostream)
    catch
        iostream = __clients__[1]["blob_client"].get_blob_to_bytes(arg.container, arg.blob.name)
        data = deserialize(IOBuffer(iostream.content))
    end
    arg.blob = data 
    return arg.blob
end


###################################################################################################
# Blob Future: reference to blob in blob storage (user-side fetch)

mutable struct BlobFuture
    container::Union{String, Nothing}
    blob
    client_index::Integer
end

BlobFuture(container, blob) = BlobFuture(container, blob, 1)
BlobFuture(container) = BlobFuture(container, nothing, 1)
BlobFuture() = BlobFuture(nothing, nothing, 1)


function fetch(arg::BlobFuture; destroy_blob=false)

    # Try to read future from disk, otherwise fetch from blob
    i = arg.client_index
    #try
        num_files = length(arg.blob.name)
        out_files = []
        for blob in arg.blob.name

            # Fetch blob and add to collection
            if ~isnothing(__clients__[i]["blob_client"])
                iostream = __clients__[i]["blob_client"].get_blob_to_bytes(arg.container, blob)
                push!(out_files, deserialize(IOBuffer(iostream.content)))

                # Delete blob (default is true)
                destroy_blob && __clients__[i]["blob_client"].delete_blob(arg.container, blob)
            end
        end
        
        if num_files > 1
            return tuple(out_files...)
        elseif length(out_files) == 1
            return out_files[1]
        else
            return nothing
        end
    #catch
        throw("Blob does not (yet) exist or BlobFuture does not contain a proper blob reference.")
    #end
end


function fetch!(arg::BlobFuture; destroy_blob=false)

    # Try to read future from disk, otherwise fetch from blob
    i = arg.client_index
    try
        num_files = length(arg.blob.name)
        out_files = []
        for blob in arg.blob.name

            # Fetch blob and add to collection
            if ~isnothing(__clients__[i]["blob_client"])
                iostream = __clients__[i]["blob_client"].get_blob_to_bytes(arg.container, blob)
                push!(out_files, deserialize(IOBuffer(iostream.content)))

                # Delete blob (default is true)
                destroy_blob && __clients__[i]["blob_client"].delete_blob(arg.container, blob)
            end
        end
        
        if num_files > 1
            arg.blob = tuple(out_files...)
        elseif length(out_files) == 1
            arg.blob = out_files[1]
        else
            arg.blob = nothing
        end
        return arg.blob 
    catch
        throw("Blob does not (yet) exist or BlobFuture does not contain a proper blob reference.")
    end
end

