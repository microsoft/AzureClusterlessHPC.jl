
# Redwood setup
ENV["PARAMETERS"] = joinpath(pwd(), "parameters.json")
using AzureClusterlessHPC, PyCall, Serialization
batch_clear()

@batchdef using BSON, PyCall, Zygote
@batchdef azureblob = pyimport("azure.storage.blob");

@batchdef begin
    using Flux
    using Flux: onehotbatch, onecold, flatten
    using Flux.Losses: logitcrossentropy
    using Flux.Data: DataLoader
    using Parameters: @with_kw
    using Statistics: mean
    using CUDA
    using MLDatasets: CIFAR10
    using MLDataPattern: splitobs
end

@batchdef ENV["DATADEPS_ALWAYS_ACCEPT"] = "true"

@batchdef function get_processed_data(args)
    x, y = CIFAR10.traindata()

    (train_x, train_y), (val_x, val_y) = splitobs((x, y), at=1-args.valsplit)

    train_x = float(train_x)
    train_y = onehotbatch(train_y, 0:9)
    val_x = float(val_x)
    val_y = onehotbatch(val_y, 0:9)
    
    return (train_x, train_y), (val_x, val_y)
end

@batchdef function get_test_data()
    test_x, test_y = CIFAR10.testdata()
   
    test_x = float(test_x)
    test_y = onehotbatch(test_y, 0:9)
    
    return test_x, test_y
end

# VGG16 and VGG19 models
@batchdef function vgg16()
    Chain(
        Conv((3, 3), 3 => 64, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(64),
        Conv((3, 3), 64 => 64, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(64),
        MaxPool((2,2)),
        Conv((3, 3), 64 => 128, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(128),
        Conv((3, 3), 128 => 128, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(128),
        MaxPool((2,2)),
        Conv((3, 3), 128 => 256, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(256),
        Conv((3, 3), 256 => 256, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(256),
        Conv((3, 3), 256 => 256, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(256),
        MaxPool((2,2)),
        Conv((3, 3), 256 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        Conv((3, 3), 512 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        Conv((3, 3), 512 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        MaxPool((2,2)),
        Conv((3, 3), 512 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        Conv((3, 3), 512 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        Conv((3, 3), 512 => 512, relu, pad=(1, 1), stride=(1, 1)),
        BatchNorm(512),
        MaxPool((2,2)),
        flatten,
        Dense(512, 4096, relu),
        Dropout(0.5),
        Dense(4096, 4096, relu),
        Dropout(0.5),
        Dense(4096, 10)
    )
end

@batchdef @with_kw mutable struct Args
    batchsize::Int = 128
    lr::Float64 = 3e-4
    epochs::Int = 50
    valsplit::Float64 = 0.1
    checkpoint = nothing
end

@batchdef function train(; kws...)
    # Initialize the hyperparameters
    args = Args(; kws...)
    if CUDA.has_cuda()
        @info "Training on GPU"
    else
        @info "Training on CPU"
    end

    if ~isnothing(args.checkpoint)
        params_check, epoch_start, opt = deserialize(args.checkpoint)
    else
        params_check = nothing; epoch_start = 1; opt = nothing
    end

    # Load the train, validation data 
    train_data, val_data = get_processed_data(args)
    train_loader = DataLoader(train_data, batchsize=args.batchsize, shuffle=true)
    val_loader = DataLoader(val_data, batchsize=args.batchsize)

    # Construct model
    @info("Constructing new Model")
    m = vgg16()
    if ~isnothing(params_check)
        @info("Load model checkpoint")
        params_m = params(m)
        for (p, pc) in zip(params_m, params_check)
            p[:] = pc
        end
    end
    m = m |> gpu

    # Loss
    loss(x, y) = logitcrossentropy(m(x), y)

    ## Training
    # Defining the optimizer
    isnothing(opt) && (opt = ADAM(args.lr))
    ps = Flux.params(m)

    @info("Training....")
    # Starting to train models
    for epoch in epoch_start:args.epochs
        @info "Epoch $epoch"

        for (x, y) in train_loader
            x, y = x |> gpu, y |> gpu
            gs = Flux.gradient(() -> loss(x,y), ps)
            Flux.update!(opt, ps, gs)
        end

        validation_loss = 0f0
        for (x, y) in val_loader
            x, y = x |> gpu, y |> gpu
            validation_loss += loss(x, y)
        end
        validation_loss /= length(val_loader)
        @show validation_loss

        # Writen current model
        checkpoint(m, epoch+1, opt, "checkpoint", "azureclusterlesstemp")
    end

    m = m |> cpu    
    return m
end


@batchdef function test(m; kws...)
    args = Args(kws...)

    test_data = get_test_data()
    test_loader = DataLoader(test_data, batchsize=args.batchsize)

    correct, total = 0, 0
    for (x, y) in test_loader
        x, y = x |> gpu, y |> gpu
        correct += sum(onecold(cpu(m(x))) .== onecold(cpu(y)))
        total += size(y, 2)
    end
    test_accuracy = correct / total

    # Print the final accuracy
    @show test_accuracy
end


@batchdef function checkpoint(model, epoch, optimizer, blob, container)

    # Blob client
    blob_client = azureblob.BlockBlobService(
        account_name = ENV["STORAGE_ACCOUNT"],
        account_key = ENV["STORAGE_KEY"]
    )

    # Move data to CPU
    model_cpu = cpu(model)
    P = params(model_cpu)
    epoch_cpu = cpu(epoch)

    # Serialize checkpoint
    iostream = open(filename, "w")
    serialize(iostream, [P, epoch, optimizer]); close(iostream)

    # Move to blob container
    blob_client.create_blob_from_path(container, blob, filename)
end


function migrate!(bctrl::BatchController, task_no, pool_no_new)

    # Get task info
    job_id = bctrl.job_id[task_no]
    task_id = bctrl.task_id[task_no]
    task_name = task_id["taskname"]
    pool_no_current = task_id["pool"]

    # Terminate task
    try
        bctrl.batch_client[task_no].task.terminate(job_id, task_name)
    catch
        print("Task already terminated.")
    end

    # Fetch checkpoint
    try
        bytes = bctrl.blob_client[pool_no_current].get_blob_to_bytes(bctrl.blobcontainer, "checkpoint")
        check = IOBuffer(bytes.content)
    catch
        check = nothing
    end

    # If existing tasks already run in new target pool, submit new task to same job ID
    if length(bctrl.job_id) < pool_no_new
        new_job_id = split(job_id, "_")[1]
        opt = Options(job_name=new_job_id, task_name_full=task_name, pool=pool_no_new)
    else
        new_job_id = bctrl.job_id[pool_no_new]
        opt = Options(job_name=new_job_id, task_name_full=task_name, pool=pool_no_new)
    end
    
    # Restart task in different pool
    bctrl_mig = @batchexec(train(; checkpoint=check), opt)
    new_job = bctrl_mig.job_id[1]
    new_task = bctrl_mig.task_id[1]
    new_output = bctrl_mig.output[1]

    # Update information in batch controller
    popat!(bctrl.task_id, task_no)
    popat!(bctrl.output, task_no)
    push!(bctrl.job_id, new_job)
    push!(bctrl.task_id, new_task)
    push!(bctrl.output, new_output)
end


#######################################################################################################################
# Train VGG16 model on CIFAR 10 data
# Example of task migration
#

# Create two pools (1 node, 0 nodes)
create_pool(num_nodes_per_pool=[1,0]);

# Submit job
bctrl = @batchexec train()

# Wait for some epochs to finish
sleep(300)  # 5 minutes

# Migrate job
task_no = 1
new_pool = 2
migrate!(bctrl, task_no, new_pool)

# Fetch result
m = fetch(bctrl)

# Test model locally
test(m)