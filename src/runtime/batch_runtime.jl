#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

# Load local AzureClusterlessHPC package
using AzureClusterlessHPC, Serialization, Distributed

if haskey(ENV, "AZ_BATCH_TASK_SHARED_DIR")
    batchdir = ENV["AZ_BATCH_TASK_SHARED_DIR"]
else
    batchdir = ENV["AZ_BATCH_TASK_WORKING_DIR"]
end

# Load packages first
try
    iostream = open(join([batchdir, "/packages.dat"]), "r")
    package_expr = deserialize(iostream)
    close(iostream)
    eval(package_expr)
catch
    nothing
end

# Load AST
filename = ENV["FILENAME"]
iostream = open(join([batchdir, "/", filename]), "r")
ast = deserialize(iostream)
close(iostream)

# Execute
eval(ast)
