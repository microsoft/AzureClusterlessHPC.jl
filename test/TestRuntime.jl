
module TestRuntime

    ENV["AZ_BATCH_TASK_WORKING_DIR"] = pwd()    # use AzureClusterlessHPC runtime
    ENV["CREDENTIALS"] = ""
    ENV["FILENAME"] = "test_expr.dat"

    using AzureClusterlessHPC, Serialization, Test

    function __init__()
        global azureclusterlesshpc_runtime = ["core/test_batch_runtime.jl"]
    end

    function  runtests()
        ENV["AZ_BATCH_TASK_WORKING_DIR"] = pwd()    # use AzureClusterlessHPC runtime

        for t=azureclusterlesshpc_runtime
            @testset "Test $t" begin
                @time include(t)
            end
        end
    end
end
