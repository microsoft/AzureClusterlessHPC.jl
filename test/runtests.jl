#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

using Test

function recompile_azureclusterlesshpc(; runtime=false)
    azureclusterlesshpc_pkgid = Base.PkgId(Base.UUID("0090f474-c28d-4577-9e1b-9155814dbffa"), "AzureClusterlessHPC")
    if runtime
        ENV["AZ_BATCH_TASK_WORKING_DIR"] = pwd()
    else
        if haskey(ENV, "AZ_BATCH_TASK_WORKING_DIR")
            delete!(ENV, "AZ_BATCH_TASK_WORKING_DIR")
        end
    end
    Base.compilecache(azureclusterlesshpc_pkgid)
end

if ARGS[1] == "core"
    
    recompile_azureclusterlesshpc(runtime=false)
    include("TestCore.jl")
    using Main.TestCore
    TestCore.runtests()

elseif ARGS[1] == "runtime"

    recompile_azureclusterlesshpc(runtime=true)
    include("TestRuntime.jl")
    using Main.TestRuntime
    TestRuntime.runtests()

else
    print("Pass \"core\" or \"runtime\".\n")
end

recompile_azureclusterlesshpc(runtime=false)