module TestCore
    
    # Environment variables
    ENV["CREDENTIALS"] = ""
    ENV["PARAMETERS"] = "params.json"

    if haskey(ENV, "AZ_BATCH_TASK_WORKING_DIR")
        delete!(ENV, "AZ_BATCH_TASK_WORKING_DIR")
    end

    using AzureClusterlessHPC, PyCall, Test, SyntaxTree, Random, Serialization

    function __init__()


        global test_suite = get(ENV, "test_suite", "core") # "all", "core", "pyinterface"

        # AzureClusterlessHPC core
        global azureclusterlesshpc_core = ["core/test_batch_controller.jl",
                        "core/test_batch_macros.jl",
                        "core/test_batch_futures.jl"]

        # AzureClusterlessHPC python interface
        global azureclusterlesshpc_pyinterface = ["pyinterface/test_pyinterface.jl"]

    end

    function runtests()
        if test_suite == "all" || test_suite == "core"
            for t=azureclusterlesshpc_core
                @testset "Test $t" begin
                    @time include(t)
                end
            end
        end

        if test_suite == "all" || test_suite == "pyinterface"
            for t=azureclusterlesshpc_pyinterface
                @testset  "Test $t" begin
                    @time include(t)
                end
            end
        end
    end

end