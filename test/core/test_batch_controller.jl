# Test batch controller
# Philipp A. Witte, Microsoft
# January 2021
#

try
    AzureClusterlessHPC == Main.TestCore.AzureClusterlessHPC
    print("Module already loaded.\n")
catch
    using AzureClusterlessHPC, PyCall, Test, SyntaxTree, Random
end

pool_id = "test_pool"
job_id = ["test_job_1", "test_job_2"]
task_id = Array{Dict, 1}(undef, 0)
push!(task_id, Dict("taskname" => "task_1", "pool" => 1)); push!(task_id, Dict("taskname" => "task_2", "pool" => 1))
num_tasks = 2
blobcontainer = "test_container"
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
batch_client = [PyObject(nothing)]
blob_client = [PyObject(nothing)]


###################################################################################################
# Constructors

function test_vars(bctrl)
    @test typeof(bctrl) <: BatchController
    @test typeof(bctrl.pool_id) <: Union{String, Array}
    @test typeof(bctrl.job_id) <: Union{Array, String}
    @test typeof(bctrl.task_id) <: Array{Dict, 1}
    @test typeof(bctrl.num_tasks) <: Integer
    @test typeof(bctrl.output) <: Array{Any, 1}
    @test typeof(bctrl.blobcontainer) <: String
    @test typeof(bctrl.batch_client) <: Union{Array, Nothing}
    @test typeof(bctrl.blob_client) <: Union{Array, Nothing}
end

# Generic constructur
bctrl = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, batch_client, blob_client)
test_vars(bctrl)

# Shortcut constructor
bctrl = BatchController(job_id, task_id, num_tasks, output)
test_vars(bctrl)

###################################################################################################
# Fetch

# Fetch for given task
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])

idx = 1
out = AzureClusterlessHPC.fetch(bctrl_empty, idx; destroy_blob=false, timeout=60, wait_for_completion=true)
@test typeof(out) == Tuple{}

# Fetch given task and overwrite input
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
@test ~isnothing(output[1].blob)
@test ~isnothing(output[2].blob)

out = AzureClusterlessHPC.fetch!(bctrl_empty, idx; destroy_blob=false, timeout=60, wait_for_completion=true)
@test isnothing(out)
@test isnothing(output[1].blob)
@test ~isnothing(output[2].blob)

# Fetch all
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
out = AzureClusterlessHPC.fetch(bctrl_empty; destroy_blob=false, timeout=60)
@test typeof(out) == Array{Any, 1}
@test length(out) == 2

# Fetch all tasks and overwrite input
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
@test ~isnothing(output[1].blob)
@test ~isnothing(output[2].blob)

out = AzureClusterlessHPC.fetch!(bctrl_empty; destroy_blob=false, timeout=60)
@test isnothing(out[1])
@test isnothing(out[2])
@test isnothing(output[1].blob)
@test isnothing(output[2].blob)

# Fetch reduce
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
AzureClusterlessHPC.fetchreduce(bctrl_empty)

# Fetch reduce overwrite input (non-tuple)
reduce = [9999]
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
out = AzureClusterlessHPC.fetchreduce!(bctrl_empty, reduce)
@test out == reduce[]

# Fetch reduce overwrite input tuple
reduce = ([8888], [9999])
output = [BlobFuture(blobcontainer, BlobRef("outfile_1")), BlobFuture(blobcontainer, BlobRef("outfile_2"))]
bctrl_empty = BatchController(pool_id, job_id, task_id, num_tasks, output, blobcontainer, [nothing], [nothing])
out = AzureClusterlessHPC.fetchreduce!(bctrl_empty, reduce)
@test out == reduce

