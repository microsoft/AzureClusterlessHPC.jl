#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

using Serialization
export BlobRef, BatchFuture, BlobFuture, fetch!, remote_reduction#, fetchreduce_batch
import Base.fetch


#######################################################################################################################
# Futures

mutable struct BlobRef
    name::Union{String, Tuple}
end

mutable struct BatchFuture
    container::String
    blob
end

function fetch(arg::BatchFuture)
    if haskey(ENV, "AZ_BATCH_TASK_SHARED_DIR")
        iostream = open(join([ENV["AZ_BATCH_TASK_SHARED_DIR"], "/", arg.blob.name]), "r")
    else
        iostream = open(arg.blob.name, "r")
    end
    data = deserialize(iostream)
    close(iostream)
    return data
end

function fetch!(arg::BatchFuture)
    if haskey(ENV, "AZ_BATCH_TASK_SHARED_DIR")
        iostream = open(join([ENV["AZ_BATCH_TASK_SHARED_DIR"], "/", arg.blob.name]), "r")
    else
        iostream = open(arg.blob.name, "r")
    end
    arg.blob = deserialize(iostream)
    close(iostream)
    return arg.blob
end

mutable struct BlobFuture
    container::String
    blob
    client_index::Integer
end

function fetch(arg::BlobFuture)

    num_files = length(arg.blob.name)
    out_files = []
    for blob in arg.blob.name

        # Fetch blob and add to collection
        if haskey(ENV, "AZ_BATCH_TASK_SHARED_DIR")
            iostream = open(join([ENV["AZ_BATCH_TASK_SHARED_DIR"], "/", blob]), "r")
        else
            iostream = open(blob, "r")
        end
        push!(out_files, deserialize(iostream))
        close(iostream)
    end
    
    if num_files > 1
        data = tuple(out_files...)
    else
        data = out_files[1]
    end
    return data
end

function fetch!(arg::BlobFuture)

    num_files = length(arg.blob.name)
    out_files = []
    for blob in arg.blob.name

        # Fetch blob and add to collection
        if haskey(ENV, "AZ_BATCH_TASK_SHARED_DIR")
            iostream = open(join([ENV["AZ_BATCH_TASK_SHARED_DIR"], "/", blob]), "r")
        else
            iostream = open(blob, "r")
        end
        push!(out_files, deserialize(iostream))
        close(iostream)
    end
    
    if num_files > 1
        arg.blob = tuple(out_files...)
    else
        arg.blob = out_files[1]
    end
    return arg.blob
end
