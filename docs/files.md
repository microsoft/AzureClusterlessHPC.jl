
# Copying and retrieving files


Aside from passing data and variables as function arguments to a batch task, it is possible to manually upload files from the local disk to a batch task. This avoids having to read a file into Julia before passing it as a function argument or broadcasting it. Similarily, it is possible to copy files from the batch worker disk back to the local disk.

## Upload files for batch task

To upload a file from the local disk to your batch tasks, use the `fileinclude` function:

```
@batchdef fileinclude("my_local_file.dat")
```

This expression first copies the file `my_local_file.dat` to the Azure blob store and then includes it as a resource file with any future batch task.

## Retrieve file from batch task

If your remotely executed Julia function saves a file to the local batch worker disk, you can use the `filereturn()` function to move that file from the disk of the batch worker to blob storage:

```
filereturn("my_remote_file.dat")
```

Note that the `filereturn` statement must be included in the function that will executed remotely as a batch task. See the following function as an example:

```
@batchdef function create_file()

    # Do some work
    data = ...

    # Write output to local file
    iostream = open("my_remote_file.dat", "w")
    write(iostream, data)

    # Copy remote file to blob store
    filereturn("my_remote_file.dat")
end
```

Similar to return arguments, files from `filereturn` will be included as a `Future` in the batch controller. Once your function has executed successfully, you can retrieve the file via:

```
# Remotely run function via azure batch
bctrl = @batchexec create_file()

# Wait for task to finish
wait_for_tasks_to_complete(bctrl)

# Copy "my_remote_file.dat" to your local disk
fetch(bctrl.files; path=pwd())
```