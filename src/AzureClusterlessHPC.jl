#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

module AzureClusterlessHPC

# If key is set, requires re-compilation
if haskey(ENV, "AZ_BATCH_TASK_WORKING_DIR")
    include("runtime/azureclusterlesshpc_light.jl")
else
    using PyCall, Serialization, JSON, Random, SyntaxTree, Logging
    import Base.fetch, Base.setindex!

    export batch_show, batch_clear, Options, fileinclude
    export delete_pool, delete_container, delete_all_jobs

    # Initiliaze PyCall constants
    const batch = PyNULL()
    const azurequeue = PyNULL()
    const azureblob = PyNULL()
    const serviceprinciple = PyNULL()
    const datetime = PyNULL()
    const batchmodels = PyNULL()
    const azureclusterlesshpc = PyNULL()

    # Variables for collecting expressions
    global __expressions__ = nothing    # collect generic expressions tagged with @batchdef
    global __packages__ = nothing   # collect "using" statements tagged with @batchdef

    # Module initialization
    include("core/parse_credentials.jl")
    
    function __init__()

        # Add path to Python module to sys env
        sys = pyimport("sys")
        sys.path = cat(sys.path, joinpath(dirname(pathof(AzureClusterlessHPC)), "pyinterface"); dims=1)

        # Load pymodules
        copy!(batch, pyimport("azure.batch"))
        copy!(azurequeue, pyimport("azure.storage.queue"))
        copy!(azureblob, pyimport("azure.storage.blob"))
        copy!(serviceprinciple, pyimport("azure.common.credentials"))
        copy!(datetime, pyimport("datetime"))
        copy!(batchmodels, batch.models)
        copy!(azureclusterlesshpc, pyimport("azureclusterlesshpc"))

        # Get credentials if environment variable is set
        try
            if haskey(ENV, "CREDENTIALS")
                global __get_credentials__ = [JSON.parsefile(ENV["CREDENTIALS"])]
            else
                global __get_credentials__ = get_credentials(joinpath(dirname(pathof(AzureClusterlessHPC))[1:end-4], "user_data"))
            end
        catch
            @warn "No credential file specified via ENV[\"CREDENTIALS\"]. All calls to cloud SDKs that require authentication will return nothing."
            global __get_credentials__ = nothing
        end
        global __credentials__ = __get_credentials__

        # Initialize global resource and blobfuture variables
        if ~isnothing(__credentials__)
            global __num_accounts__ = length(__credentials__)
        else
            global __num_accounts__ = 0
        end
        
        global __resources__ = Array{Any}(undef, __num_accounts__)
        for i=1:__num_accounts__
            __resources__[i] = []
        end

        # Read parameters
        try
            if haskey(ENV, "PARAMETERS")
                user_params = JSON.parsefile(ENV["PARAMETERS"])
            else
                user_params = Dict()
            end
            global __get_params__ = create_parameter_dict(user_params, default_parameters)
        catch
            global __get_params__ = nothing
        end
        global __params__ = __get_params__

        # Create storage container
        try
            global __get_container__ = __params__["_BLOB_CONTAINER"]    # Azure container for temporary files
        catch
            global __get_container__ = nothing
        end
        global __container__ = __get_container__

        if __params__["_VERBOSE"] == "1"
            global __verbose__ = true
        else
            global __verbose__ = false
        end

        # Global list of pools (start with no pools)
        global __active_pools__ = Array{Dict}(undef, 0)

        # Batch and blob clients
        global __clients__ = create_clients(__credentials__, batch=true, blob=true)
    end

    # Includes
    include("pyinterface/pyinterface.jl")
    include("pyinterface/pyinterface_test.jl")
    include("core/azureclusterlesshpc_base.jl")
    include("core/futures.jl")
    include("core/batch_controller.jl")
    include("core/batch_macros.jl")
    include("core/batch_shortcuts.jl")
    include("core/batch_fetch.jl")
end
end