# Test batch runtime
# Philip A. Witte, Microsoft
# January 2021
#

try
    AzureClusterlessHPC == Main.TestRuntime.AzureClusterlessHPC
catch
    ENV["AZ_BATCH_TASK_WORKING_DIR"] = pwd()
    ENV["FILENAME"] = "test_expr.dat"
    using AzureClusterlessHPC, Serialization, Test
end

# Test batch runtime main()
expr = :(print("Hello world"))
_iostream = open("test_expr.dat", "w")
serialize(_iostream, expr)
close(_iostream)

include("../../src/runtime/batch_runtime.jl")
run(`rm test_expr.dat`)

# Test blob reference
string_name = "test_blobref"
blobref_string = BlobRef(string_name)
@test typeof(blobref_string) ==  BlobRef
@test  blobref_string.name == string_name

tuple_name = ("test_blobref_1", "test_blobref_2")
blobref_tuple = BlobRef(tuple_name)
@test typeof(blobref_tuple) ==  BlobRef
@test  blobref_tuple.name == tuple_name

# Batch future
container = "test_container"
batchfuture = BatchFuture(container, blobref_string)
@test typeof(batchfuture) == BatchFuture
@test batchfuture.container == container
@test typeof(batchfuture.blob) == BlobRef
@test batchfuture.blob.name == string_name

# Fetch and inplace fetch
A = randn(2, 2)
_iostream = open(string_name, "w")
serialize(_iostream, A)
close(_iostream)

out = fetch(batchfuture)
@test out == A
@test typeof(batchfuture.blob) == BlobRef
@test batchfuture.blob.name == string_name

out = fetch!(batchfuture)
@test out == A
@test batchfuture.blob == A

# Blob future
string_name = ["test_blobref"]
blobfuture_single = BlobFuture(container, BlobRef(tuple(string_name...)), 1)
@test typeof(blobfuture_single) == BlobFuture
@test blobfuture_single.container == container
@test typeof(blobfuture_single.blob) == BlobRef
@test blobfuture_single.blob.name == tuple(string_name...)

tuple_name = ["test_blobref_1", "test_blobref_2"]
blobfuture_tuple = BlobFuture(container, BlobRef(tuple(tuple_name...)), 1)
@test typeof(blobfuture_tuple) == BlobFuture
@test blobfuture_tuple.container == container
@test typeof(blobfuture_tuple.blob) == BlobRef
@test blobfuture_tuple.blob.name == tuple(tuple_name...)

# Fetch
out1 = fetch(blobfuture_single)
@test typeof(blobfuture_single.blob) == BlobRef
@test blobfuture_single.blob.name == tuple(string_name...)

out2 = fetch!(blobfuture_single)
@test blobfuture_single.blob == A

# Remove temp files
run(`rm test_blobref`)
