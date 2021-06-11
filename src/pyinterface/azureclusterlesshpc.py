#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

import azure.storage.blob as azureblob
import azure.storage.queue as azurequeue
import azure.batch.models as batchmodels
import azure.batch as batch
from azure.common.credentials import ServicePrincipalCredentials
import azure.batch._batch_service_client as batchServiceClient
import datetime, os, sys, time, warnings


###################################################################################################
# Create clients

def create_batch_client(credentials):

    credentials_batch = ServicePrincipalCredentials(
        client_id = credentials['_AD_BATCH_CLIENT_ID'],
        secret = credentials['_AD_SECRET_BATCH'],
        tenant = credentials['_AD_TENANT'],
        resource = credentials['_BATCH_RESOURCE']
    )

    # Batch client
    batch_client = batch.BatchServiceClient(
        credentials_batch,
        batch_url = credentials['_BATCH_ACCOUNT_URL']
    )
    return batch_client


def create_blob_client(credentials):

    # Storage blob client (cannot be AAD based)
    blob_client = azureblob.BlockBlobService(
        account_name = credentials['_STORAGE_ACCOUNT_NAME'],
        account_key = credentials['_STORAGE_ACCOUNT_KEY']
    )
    return blob_client


def create_queue_client(credentials):

    # Storage queue client
    queue_client = azurequeue.QueueService(
        account_name = credentials['_STORAGE_ACCOUNT_NAME'],
        account_key = credentials['_STORAGE_ACCOUNT_KEY']
    )
    return queue_client


# Collect clients in dictionary
def create_clients(credentials, batch=False, blob=False, queue=False):

    if batch is False:
        batch_client = None
    else:
        batch_client = create_batch_client(credentials)

    if blob is False:
        blob_client = None
    else:
        blob_client = create_blob_client(credentials)

    if queue is False:
        queue_client = None
    else:
        queue_client = create_queue_client(credentials)

    return {"batch_client": batch_client, "blob_client": blob_client, "queue_client": queue_client}


###################################################################################################
# Blob stuff

# Fine
def create_blob_containers(blob_client, container_name_list):
    for container in container_name_list:
        blob_client.create_container(container, fail_on_exist=False)
    return True

# Conflict
def create_sas_token(
        blob_client, container_name, blob_name, permission, expiry=None,
        timeout=None):

    if expiry is None:
        if timeout is None:
            timeout = 30
        expiry = datetime.datetime.utcnow() + datetime.timedelta(
            minutes=timeout)
    return blob_client.generate_blob_shared_access_signature(
        container_name, blob_name, permission=permission, expiry=expiry)

# Conflict
def upload_blob_and_create_sas(
        blob_client, container_name, blob_name, file_name, expiry,
        timeout=None):

    blob_client.create_container(
        container_name,
        fail_on_exist=False)

    blob_client.create_blob_from_path(
        container_name,
        blob_name,
        file_name)

    sas_token = create_sas_token(
        blob_client,
        container_name,
        blob_name,
        permission=azureblob.BlobPermissions.READ,
        expiry=expiry,
        timeout=timeout)



    sas_url = blob_client.make_blob_url(
        container_name,
        blob_name,
        sas_token=sas_token)

    return sas_url

# Conflict
def upload_files_to_blob(blob_client, container_name, file_paths, verbose=True):

    blob_names = list()
    for path_to_file in file_paths:
        blob_name = os.path.basename(path_to_file)

        if verbose:
            print('Uploading file {} to blob container [{}]...'.format(path_to_file, container_name))

        blob_client.create_blob_from_path(container_name, blob_name, path_to_file)
        blob_names.append(blob_name)

    return blob_names

# Fine
def upload_bytes_to_container(blob_client, container_name, blob_name, blob, verbose=True):
    if verbose:
        print('Uploading file {} to container [{}]...'.format(blob_name, container_name))
    
    blob_client.create_blob_from_bytes(container_name, blob_name, bytes(blob))
    return [blob_name]


#  Fine
def create_blob_url(blob_client, container_name, blob_list):

    sas_urls = list()
    for blob_name in blob_list:
        sas_token = blob_client.generate_blob_shared_access_signature(
            container_name,
            blob_name,
            permission=azureblob.BlobPermissions.READ,
            expiry=datetime.datetime.utcnow() + datetime.timedelta(hours=99))

        sas_urls.append(blob_client.make_blob_url(container_name,
                                                blob_name,
                                                sas_token=sas_token))
    return sas_urls


# Conflict
def get_container_sas_token(blob_client, container_name, blob_permissions):

    # Obtain the SAS token for the container, setting the expiry time and
    # permissions. In this case, no start time is specified, so the shared
    # access signature becomes valid immediately. Expiration is in 2 hours.
    container_sas_token = \
        blob_client.generate_container_shared_access_signature(
            container_name,
            permission=blob_permissions,
            expiry=datetime.datetime.utcnow() + datetime.timedelta(hours=2))

    return container_sas_token


# Fine
def get_container_sas_url(blob_client, storage_account_name, container_name, blob_permissions):

    # Obtain the SAS token for the container.
    sas_token = get_container_sas_token(blob_client, container_name, azureblob.BlobPermissions.WRITE)

    # Construct SAS URL for the container
    container_sas_url = "https://{}.blob.core.windows.net/{}?{}".format(storage_account_name, container_name, sas_token)

    return container_sas_url


# Fine
def create_batch_output_file(blob_client, storage_account_name, container_name, filename):
    
    output_container_sas_url = get_container_sas_url(blob_client, storage_account_name, container_name, 
        azureblob.BlobPermissions.WRITE)

    destination = batchmodels.OutputFileDestination(container = 
        batchmodels.OutputFileBlobContainerDestination(container_url=output_container_sas_url))
    
    upload_options = batchmodels.OutputFileUploadOptions(upload_condition=batchmodels.OutputFileUploadCondition.task_success)
    output_files = batchmodels.OutputFile(file_pattern=filename, destination=destination, upload_options=upload_options)

    return [output_files]


###################################################################################################
# Batch pool stuff

# Fine
# Create resource file for pool
def create_pool_resource_file(blob_client, path_to_file, container_name):

    # Upload pool startup script
    timeout = datetime.datetime.utcnow() + datetime.timedelta(hours=1)
    object_name = path_to_file.split("/")[-1]
    setup_sas = upload_blob_and_create_sas(blob_client, container_name, object_name, path_to_file, timeout)

    # Create resource file
    resource_files = [batchmodels.ResourceFile(
        http_url = setup_sas,
        file_path = "/home/setup.sh"
        )]
    return resource_files


# Conflict
# Get latest VM image info
def select_latest_verified_vm_image_with_node_agent_sku(
        batch_client, publisher, offer, sku_starts_with):

    # get verified vm image list and node agent sku ids from service
    options = batchmodels.AccountListSupportedImagesOptions(
        filter="verificationType eq 'verified'")
    images = batch_client.account.list_supported_images(
        account_list_supported_images_options=options)

    # pick the latest supported sku
    skus_to_use = [
        (image.node_agent_sku_id, image.image_reference) for image in images
        if image.image_reference.publisher.lower() == publisher.lower() and
        image.image_reference.offer.lower() == offer.lower() and
        image.image_reference.sku.startswith(sku_starts_with)
    ]

    # pick first
    agent_sku_id, image_ref_to_use = skus_to_use[0]
    return (agent_sku_id, image_ref_to_use)

# Fine
# Create pool
def create_pool(batch_service_client, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
    node_os_offer, node_os_sku, image_resource_id=None, enable_inter_node=False, resource_files=None,
    enable_auto_scale=False, auto_scale_formula=None, auto_scale_evaluation_interval_minutes=None,
    container=None, container_registry=None):

    # Configure the start task for the pool
    user = batchmodels.AutoUserSpecification(
        scope=batchmodels.AutoUserScope.pool,
        elevation_level=batchmodels.ElevationLevel.admin
    )

    if auto_scale_evaluation_interval_minutes is not None:
        autoscale_interval = datetime.timedelta(minutes=auto_scale_evaluation_interval_minutes)
    else:
        autoscale_interval = None

    # As starttask, run the setup script
    if resource_files is not None:
        start_task = batchmodels.StartTask(
            command_line='/home/setup.sh',
            user_identity=batchmodels.UserIdentity(auto_user=user),
            wait_for_success=True,
            resource_files=resource_files
        )
    else:
        start_task = None

    agent_sku_id, ir = select_latest_verified_vm_image_with_node_agent_sku(
        batch_service_client, node_os_publisher, node_os_offer, node_os_sku
    )

    # Container image
    if container is not None:
        if container_registry is not None:
            container_conf = batchmodels.ContainerConfiguration(container_image_names=[container],
                container_registries=[container_registry])
        else:
            container_conf = batchmodels.ContainerConfiguration(container_image_names=[container])        
    else:
        container_conf = None

    # Use custom image ref if an image resource ID is provided
    if image_resource_id is not None:
        ir = batchmodels.ImageReference(
           virtual_machine_image_id = image_resource_id
       )

    # Create the VirtualMachineConfiguration
    vmc = batchmodels.VirtualMachineConfiguration(
        image_reference=ir,
        node_agent_sku_id=agent_sku_id,
        container_configuration=container_conf
    )

    # Create the unbound pool
    new_pool = batchmodels.PoolAddParameter(
        id=pool_id,
        vm_size=pool_vm_size,
        target_dedicated_nodes=pool_node_count,
        virtual_machine_configuration=vmc,
        start_task=start_task,
        max_tasks_per_node=1,
        enable_inter_node_communication=enable_inter_node,
        application_package_references=[],
        enable_auto_scale=enable_auto_scale,
        auto_scale_formula=auto_scale_formula,
        auto_scale_evaluation_interval=autoscale_interval
    )
    batch_service_client.pool.add(new_pool)
    return True


# Fine
# Create first a resource file and then the pool
def create_pool_and_resource_file(clients, pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
    node_os_offer, node_os_sku, file_name, container_name, image_resource_id=None, enable_inter_node=False,
    enable_auto_scale=False, auto_scale_formula=None, auto_scale_evaluation_interval_minutes=None,
    container=None, container_registry=None):

    resource_file = create_pool_resource_file(clients["blob_client"], file_name, container_name)

    create_pool(clients["batch_client"], pool_id, pool_vm_size, pool_node_count, node_os_publisher, 
        node_os_offer, node_os_sku, image_resource_id=image_resource_id, enable_inter_node=enable_inter_node, 
        resource_files=resource_file, enable_auto_scale=enable_auto_scale, auto_scale_formula=auto_scale_formula, 
        auto_scale_evaluation_interval_minutes=auto_scale_evaluation_interval_minutes, container=container,
        container_registry=container_registry)


# Fine
# Enable auto-scaling
def enable_auto_scale(batch_client, pool_id, auto_scale_formula, auto_scale_evaluation_interval_minutes=5):

    # Auto-scale interval
    autoscale_interval = datetime.timedelta(minutes=auto_scale_evaluation_interval_minutes)

    batch_client.pool.enable_auto_scale(pool_id, auto_scale_formula=auto_scale_formula,
                                        auto_scale_evaluation_interval=autoscale_interval,
                                        pool_enable_auto_scale_options=None,
                                        custom_headers=None, raw=False)


# Fine
# Resize pool
def resize_pool(batch_client, pool_id, target_dedicated_nodes, target_low_priority_nodes, resize_timeout_minutes=None, node_deallocation_option=None, pool_resize_options=None):
    
    if resize_timeout_minutes is not None:
        resize_timeout = datetime.timedelta(minutes=resize_timeout_minutes)
    else:
        resize_timeout = None

    pool_resize_parameter = batchmodels.PoolResizeParameter(target_dedicated_nodes = target_dedicated_nodes, target_low_priority_nodes = target_low_priority_nodes,
        resize_timeout=resize_timeout, node_deallocation_option=node_deallocation_option)

    batch_client.pool.resize(pool_id, pool_resize_parameter, pool_resize_options=pool_resize_options)



###################################################################################################
# Batch job stuff

def create_batch_resource_from_blob_url(shared_url, shared_blob):
    shared_resource = [batchmodels.ResourceFile(http_url=shared_url[i], file_path=shared_blob[i]) for i in range(0, 1)]
    return shared_resource


def create_batch_resource_from_file(blob_client, container, shared_file, verbose=True):

    # Upload to blob and create url
    shared_blob = upload_files_to_blob(blob_client, container, [shared_file], verbose=verbose)
    shared_url = create_blob_url(blob_client, container, shared_blob)

    # Create batch resource
    shared_resource = [batchmodels.ResourceFile(http_url=shared_url[i], file_path=shared_blob[i]) for i in range(0, 1)]

    return shared_resource


def create_batch_resource_from_bytes(blob_client, container, blob_name, blob, verbose=True):

    # Upload to blob and create url
    shared_blob = upload_bytes_to_container(blob_client, container, blob_name, blob, verbose=verbose)
    shared_url = create_blob_url(blob_client, container, shared_blob)

    # Create batch resource
    shared_resource = [batchmodels.ResourceFile(http_url=shared_url[i], file_path=shared_blob[i]) for i in range(0, 1)]

    return shared_resource


def create_batch_resource_from_blob(blob_client, container, shared_blob):

    # Upload to blob and create url
    shared_url = create_blob_url(blob_client, container, [shared_blob])[0]

    # Create batch resource
    shared_resource = [batchmodels.ResourceFile(http_url=shared_url, file_path=shared_blob)]

    return shared_resource


def create_batch_job(batch_client, job_id, pool_id, uses_task_dependencies=False, priority=0, verbose=True):

    try: 
        if verbose:
            print('Creating job [{}]...'.format(job_id))

        job = batchServiceClient.models.JobAddParameter(
            id=job_id,
            priority=priority,
            pool_info=batchServiceClient.models.PoolInformation(pool_id=pool_id),
            uses_task_dependencies=uses_task_dependencies)

        batch_client.job.add(job)
    except:
        if verbose:
            print('Job already exists.')


def create_task_constraint(max_wall_clock_time=None, retention_time=None, max_task_retry_count = 0):
    return batchmodels.TaskConstraints(max_wall_clock_time=max_wall_clock_time, retention_time=retention_time, 
        max_task_retry_count = max_task_retry_count)


def create_batch_task(resource_files=None, environment_variables=None, application_cmd=None, output_files=None, taskname='task', task_constraints=None, num_nodes_per_task=1, docker_container=None):

    if application_cmd is None:
        application_cmd = "/bin/bash -c \":\""  # do nothing

    # Multi-instance settings
    if num_nodes_per_task > 1:
        multi_instance_settings = batchmodels.MultiInstanceSettings(
            number_of_instances=num_nodes_per_task,
            coordination_command_line="/bin/bash -c \":\"",
            common_resource_files=resource_files[1:]
        )
        resource_files_task = [resource_files[0]]
    else:
        multi_instance_settings = None
        resource_files_task = resource_files

    # User
    if docker_container is not None:
        elevation_level = batchmodels.ElevationLevel.admin
    else:
        elevation_level = batchmodels.ElevationLevel.non_admin

    user = batchmodels.AutoUserSpecification(
        scope=batchmodels.AutoUserScope.pool,
        elevation_level=elevation_level
    )

    if docker_container is not None:
       task_container_setting = batchmodels.TaskContainerSettings(image_name=docker_container)
    else:
        task_container_setting = None

    # Create task for batch job
    task = batchServiceClient.models.TaskAddParameter(
        id = taskname,
        command_line = application_cmd, 
        user_identity = batchmodels.UserIdentity(auto_user=user),
        resource_files = resource_files_task, 
        multi_instance_settings = multi_instance_settings,
        output_files = output_files,
        environment_settings = environment_variables,
        constraints = task_constraints,
        container_settings=task_container_setting
        )

    return task

# Wait for tasks to complete
def wait_for_tasks_to_complete(batch_service_client, job_id, timedelta_minutes, verbose=True, num_restart=0):

    timeout = datetime.timedelta(minutes=timedelta_minutes)
    timeout_expiration = datetime.datetime.now() + timeout
    task_retries = {}

    if verbose:
        print("Monitoring all tasks for 'Completed' state, timeout in {}..."
            .format(timeout), end='')

    while datetime.datetime.now() < timeout_expiration:
        if verbose:
            print('.', end='')
        sys.stdout.flush()
        tasks = batch_service_client.task.list(job_id)
        incomplete_tasks = []
        failed_tasks = []

        # Check if tasks completed or failed and restart is task is eligible
        for task in tasks:
            if task.state == batchmodels.TaskState.completed:
                if task.execution_info.result == batchmodels.TaskExecutionResult.failure:

                    # Restart task
                    if task_retries.get(task.id) is None:
                        retry_count = 0
                    else:
                        retry_count = task_retries[task.id]

                    if retry_count < num_restart:
                        if verbose:
                            print('\nRestart task no ', task.id)
                        batch_service_client.task.reactivate(job_id, task.id)
                        incomplete_tasks.append(task.id)
                        task_retries.update({task.id: retry_count + 1})
                    else:
                        failed_tasks.append(task.id)
            else:
                incomplete_tasks.append(task.id)
        if not incomplete_tasks:
            if verbose:
                print()
            if len(failed_tasks) > 0:
                return failed_tasks
            else:
                return True
        else:
            time.sleep(1)
    if verbose:
        print()
    warnings.warn("Task did not reach 'Completed' state within "
                       "timeout period of " + str(timeout))
    return False


def wait_for_task_to_complete(batch_service_client, job_id, task_id, timedelta_minutes, verbose=True, num_restart=0):

    timeout = datetime.timedelta(minutes=timedelta_minutes)
    timeout_expiration = datetime.datetime.now() + timeout
    task_retries = 0
    
    if verbose:
        print("Monitoring task {} for 'Completed' state, timeout in {}..."
            .format(task_id, timeout), end='')

    while True:
        if verbose:
            print('.', end='')
        sys.stdout.flush()
        task = batch_service_client.task.get(job_id, task_id)

        # Check if task has terminated and restart if applicable
        if task.state == batchmodels.TaskState.completed:
            if task.execution_info.result == batchmodels.TaskExecutionResult.failure:
                if task_retries < num_restart:
                    batch_service_client.task.reactivate(job_id, task.id)
                    timeout_expiration = datetime.datetime.now() + timeout  # reset timeout
                    task_retries += 1
                    if verbose:
                        print('\nRestart task no ', task.id)
                else:
                    if verbose:
                        print()
                    return False
            else:
                if verbose:
                    print()
                return True
        else:
            time.sleep(1)

        # Restart after timeout?
        if datetime.datetime.now() >= timeout_expiration:
            if task_retries < num_restart:
                task = batch_service_client.task.get(job_id, task_id)
                if task.state != batchmodels.TaskState.completed:
                    batch_service_client.task.terminate(job_id, task.id)
                batch_service_client.task.reactivate(job_id, task.id)
                timeout_expiration = datetime.datetime.now() + timeout
                task_retries += 1
                if verbose:
                    print('\nTask has timed out. Restart task ', task.id)
            else:
                if verbose:
                    print()
                warnings.warn("Task did not reach 'Completed' state within "
                    "timeout period of " + str(timeout))
                return False


# def wait_for_one_task_to_complete(batch_service_client, job_id, task_id_list, timedelta_minutes, verbose=True, num_restart=0):

#     timeout = datetime.timedelta(minutes=timedelta_minutes)
#     timeout_expiration = datetime.datetime.now() + timeout
#     task_retries = {}

#     while datetime.datetime.now() < timeout_expiration:
#         if verbose:
#             print('.', end='')
#         sys.stdout.flush()

#         is_complete = False

#         for task_id in task_id_list:
#             task = batch_service_client.task.get(job_id, task_id)
#             is_complete = task.state == batchmodels.TaskState.completed

#             if is_complete:            
#                 if task.execution_info.result == batchmodels.TaskExecutionResult.failure:
#                     if task_retries.get(task.id) is None:
#                         retry_count = 0
#                     else:
#                         retry_count = task_retries[task.id]

#                     if retry_count < num_restart:
#                         batch_service_client.task.reactivate(job_id, task.id)
#                         task_retries.update({task.id: retry_count + 1})
#                         if verbose:
#                             print('\nRestart task no ', task.id)
#                     else:
#                         warnings.warn("Task failed after maximum number of retries.")
#                         return task_id, False
#                 else:
#                     return task_id, True

#         # No completed task found -> sleep and try again
#         time.sleep(1)
#     if verbose:        
#         print()
#     warnings.warn("Task did not reach 'Completed' state within "
#                        "timeout period of " + str(timeout))
#     return None, False


def wait_for_one_task_from_multi_pool(batch_service_clients, job_id, task_id_list, timedelta_minutes, verbose=True, num_restart=0):

    timeout = datetime.timedelta(minutes=timedelta_minutes)
    timeout_expiration = datetime.datetime.now() + timeout
    task_retries = {}

    while datetime.datetime.now() < timeout_expiration:
        if verbose:
            print('.', end='')
        sys.stdout.flush()

        is_complete = False

        for task_id in task_id_list:
            pool_no = task_id['pool'] - 1
            task_name = task_id['taskname']

            if type(job_id) == str:
                task = batch_service_clients[pool_no].task.get(job_id, task_name)
            else:
                task = batch_service_clients[pool_no].task.get(job_id[pool_no], task_name)
            is_complete = task.state == batchmodels.TaskState.completed
            if is_complete:            
                if task.execution_info.result == batchmodels.TaskExecutionResult.failure:
                    if task_retries.get(task.id) is None:
                        retry_count = 0
                    else:
                        retry_count = task_retries[task.id]

                    if retry_count < num_restart:
                        if type(job_id) == str:
                            batch_service_clients[pool_no].task.reactivate(job_id, task.id)
                        else:
                            batch_service_clients[pool_no].task.reactivate(job_id[pool_no], task.id)
                        task_retries.update({task.id: retry_count + 1})
                        if verbose:
                            print('\nRestart task no ', task.id)
                    else:
                        warnings.warn("Task failed after maximum number of retries.")
                        return task_name, pool_no, False
                else:
                    return task_name, pool_no, True
        # No completed task found -> sleep and try again
        time.sleep(1)
    if verbose:        
        print()
    warnings.warn("Task did not reach 'Completed' state within "
                       "timeout period of " + str(timeout))
    return None, None, False


def wait_for_one_task_from_multi_jobs(batch_service_client, job_id_list, task_id_list, timedelta_minutes, verbose=True, num_restart=0):

    timeout = datetime.timedelta(minutes=timedelta_minutes)
    timeout_expiration = datetime.datetime.now() + timeout
    task_retries = {}

    while datetime.datetime.now() < timeout_expiration:
        if verbose:
            print('.', end='')
        sys.stdout.flush()

        is_complete = False

        for job_id, task_id in zip(job_id_list, task_id_list):
            task = batch_service_client.task.get(job_id, task_id['taskname'])
            is_complete = task.state == batchmodels.TaskState.completed

            if is_complete:            
                if task.execution_info.result == batchmodels.TaskExecutionResult.failure:
                    if task_retries.get(task.id) is None:
                        retry_count = 0
                    else:
                        retry_count = task_retries[task.id]

                    if retry_count < num_restart:
                        batch_service_client.task.reactivate(job_id, task.id)
                        task_retries.update({task.id: retry_count + 1})
                        if verbose:
                            print('\nRestart task no ', task.id)
                    else:
                        warnings.warn("Task failed after maximum number of retries.")
                        return task_id['taskname'], job_id, False
                else:
                    return task_id['taskname'], job_id, True
        # No completed task found -> sleep and try again
        time.sleep(1)
    if verbose:        
        print()
    warnings.warn("Task did not reach 'Completed' state within "
                       "timeout period of " + str(timeout))
    return None, None, False


# Environment variables
def create_batch_env(name, value):
    return [batchmodels.EnvironmentSetting(name=name, value=value)]

def create_batch_envs(names, values):
    envs = []
    for (name, value) in zip(names, values):
        envs.append(batchmodels.EnvironmentSetting(name=name, value=value))
    return envs