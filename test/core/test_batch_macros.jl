#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

try
    AzureClusterlessHPC == Main.TestCore.AzureClusterlessHPC
catch
    ENV["PARAMETERS"] = joinpath(pwd()[1:end-4], "params.json")
    using AzureClusterlessHPC, PyCall, Test, SyntaxTree, Random, Serialization
end



###################################################################################################
# Concatenate expressions

# Case 1 (no current expressions)
AzureClusterlessHPC.batch_clear()
@test isnothing(AzureClusterlessHPC.__packages__)

expr = :(using Test)
AzureClusterlessHPC.append_batchdef_expression(expr)

@test AzureClusterlessHPC.__packages__.head == :block
@test AzureClusterlessHPC.__packages__.args[1].args[3].args[1].args[1] == :Test


# Case 2 (prior expression)
AzureClusterlessHPC.batch_clear()
@batchdef a = 1     # add some prior expression to AST
@test isnothing(AzureClusterlessHPC.__packages__)

expr = :(using Test)
AzureClusterlessHPC.append_batchdef_expression(expr)

@test AzureClusterlessHPC.__packages__.head == :block
@test AzureClusterlessHPC.__packages__.args[1].args[3].args[1].args[1] == :Test


###################################################################################################
# Expressions

AzureClusterlessHPC.batch_clear()

# Set index
expr = :(1 + 1)
@test expr.args[2] == 1
expr[2] = 2
@test expr.args[2] == 2

# Set index for subexpressions
expr = :((1 + 1), (2 + 2))
@test expr.args[1].args[2] == 1
expr[[1,2]] = 2
@test expr.args[1].args[2] == 2

# Locate symbol
level = []
locations = []
symbols = []
index_symbol = :i

expr = :(
    pmap(i -> hello_world(i, arg1, arg2, arg3; kwargs...), 1:10)
)

num_symbols = 4
AzureClusterlessHPC.locate_symbols!(expr, level, locations, symbols; symbol_exception=index_symbol)
@test length(locations) == num_symbols
@test locations[1] == [2,2,2,2,1,1]
@test locations[2] == [2,2,2,4]
@test locations[3] == [2,2,2,5]
@test locations[4] == [2,2,2,6]
@test symbols == [:kwargs, :arg1, :arg2, :arg3]

# Locate symbol w/o index symbol
level = []
locations = []
symbols = []

num_symbols = 6
AzureClusterlessHPC.locate_symbols!(expr, level, locations, symbols; symbol_exception=nothing)
@test length(locations) == num_symbols
@test locations[1] == [2,1]
@test locations[2] == [2,2,2,2,1,1]
@test locations[3] == [2,2,2,3]
@test locations[4] == [2,2,2,4]
@test locations[5] == [2,2,2,5]
@test locations[6] == [2,2,2,6]
@test symbols == [:i, :kwargs, :i, :arg1, :arg2, :arg3]


# Replace given symbol in AST
expr = :(
    pmap(i -> hello_world(i, arg1, arg2, arg3; kwargs...), 1:10)
)
symbol = :arg1
val = 1

@test expr.args[2].args[2].args[2].args[4] == :arg1
replace_symbol_in_expression!(expr, symbol, val)
@test expr.args[2].args[2].args[2].args[4] == val


# If array in exression in indexed, extract indexed symbol_exception
A = randn(2,2)
expr = :(
    hello_world(A[:, 1])
)
replace_symbol_in_expression!(expr, :A, A)  # replace symbol for A with array
replace_symbol_in_expression!(expr, :(:), :)  # replace symbol for indexing

@test size(expr.args[2].args[1]) == size(A)
eval_symbol_get_index!(expr)
@test size(expr.args[2]) == size(A[:, 1])


# Create macro expansion for single-task expression
AzureClusterlessHPC.batch_clear()
expr_single = :(
    hello_world(arg1, arg2, arg3; kwargs...)
)
task_expr_single = AzureClusterlessHPC.create_single_task_expression_list(expr_single)
@test typeof(task_expr_single) == Expr
@test length(task_expr_single.args) == 7


# Create macro expansion for multi-task expression
AzureClusterlessHPC.batch_clear()
expr_multi = :(
    pmap(i -> hello_world(i, arg1, arg2, arg3; kwargs...), 1:10)
)
task_expr_multi = AzureClusterlessHPC.create_multi_task_expression_list_pmap(expr_multi)
@test typeof(task_expr_multi) == Expr
@test length(task_expr_multi.args) == 6

# Macro expansion for generic expression
task_expr = AzureClusterlessHPC.create_expression_to_submit_batch_job(expr_single)
@test typeof(task_expr) == Expr
@test length(task_expr.args) == 7

task_expr = AzureClusterlessHPC.create_expression_to_submit_batch_job(expr_multi)
@test typeof(task_expr) == Expr
@test length(task_expr.args) == 6


# Submit batch job
AzureClusterlessHPC.batch_clear()
push!(AzureClusterlessHPC.__active_pools__, Dict("pool_id" => 1, "clients" => AzureClusterlessHPC.__clients__[1], "credentials" =>  nothing, "resources" => [nothing]))
function hello_world(name1, name2; kwargs...)
    print("Hello ", name1, " and ", name2)
    return name1
end

name1 = "Bob"
name2 = "Jane"
kwargs = (kw1 = 1, kw2 = 2)

expr = :(pmap(i -> hello_world(name1, name2; kwargs...), 1:10))
task_expr = AzureClusterlessHPC.create_expression_to_submit_batch_job(expr)
bctrl = eval(task_expr)

@test typeof(bctrl) == BatchController
@test typeof(bctrl.output[1]) == BlobFuture
@test length(bctrl.output) == 10
@test bctrl.num_tasks == 10


#######################################################################################################################
# Output

# Write
expr = :(
    function hello_world(arg1, arg2; kwargs...)
        out = arg1 + arg2
        write(IOBuffer(), out)
    end
)

filenames = []
AzureClusterlessHPC.find_output_files!(expr, filenames)
@test length(filenames) == 1
@test typeof(filenames[1]) == String

# Replace "return"
expr = :(
    function hello_world(arg1, arg2; kwargs...)
        out1 = arg1 + arg2
        out2 = arg1 - arg2
        return out1, out2
    end
)
@test expr.args[2].args[7].head == :return

filelist = []
AzureClusterlessHPC.replace_return_with_serialization!(expr, filelist)
linefilter!(expr)
@test expr.args[2].head == :block
@test expr.args[2].args[4].args[1] == :serialize


# Replace "return" for given function name
expr = :(
    function hello_world(arg1, arg2; kwargs...)
        out1 = arg1 + arg2
        out2 = arg1 - arg2
        return out1, out2
    end
)
@test expr.args[2].args[7].head == :return

fname = :hello_world
filelist = []
AzureClusterlessHPC.find_function_in_ast_and_replace_return!(expr, fname, filelist)
linefilter!(expr)

@test length(filelist) == 2
@test typeof(filelist[1]) == String
@test expr.args[2].head == :block
@test expr.args[2].args[4].args[1] == :serialize


#######################################################################################################################
# Bcast

# Broadcasting
AzureClusterlessHPC.batch_clear()

expr = :(A)
bcast_expr = AzureClusterlessHPC.bcast_expression(expr)
linefilter!(bcast_expr)

@test bcast_expr.head == :escape
@test bcast_expr.args[1].head == :block
@test length(bcast_expr.args[1].args) == 5
