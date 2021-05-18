#  ------------------------------------------------------------------------------------------
#  Copyright (c) Microsoft Corporation. All rights reserved.
#  Licensed under the MIT License (MIT). See LICENSE in the repo root for license information.
#  ------------------------------------------------------------------------------------------

using JSON

export get_credentials

function scan_for_credentials(path)

    # Get storage and batch accounts
    batch_accounts = []
    storage_accounts = []
    files = readdir(path)

    for entry in files
        if ~isempty(findall("aad_", entry))
            push!(batch_accounts, entry)
        elseif ~isempty(findall("key_", entry))
            push!(storage_accounts, entry)
        end
    end
    return storage_accounts, batch_accounts
end

function get_storage_credentials(path, credential_file)

    io = open(joinpath(path, credential_file), "r")
    creds = JSON.parse(io)
    storage_account_name = creds[3]["accountName"]
    storage_secret_key = creds[1]["value"]

    return storage_account_name, storage_secret_key
end

function get_batch_credentials(path, credential_file)

    io = open(joinpath(path, credential_file), "r")
    creds = JSON.parse(io)
    batch_account_name = creds[2]["accountName"]
    region = creds[2]["region"]
    tenant = creds[1]["tenant"]
    appId = creds[1]["appId"]
    password = creds[1]["password"]

    return batch_account_name, region, tenant, appId, password
end

# Scan directory for given path for credential files and return list of credentials
function get_credentials(path)

    storage_accounts, batch_accounts = scan_for_credentials(path)
    credentials = []

    if length(storage_accounts) == length(batch_accounts)
        for (storage, batch) in zip(storage_accounts, batch_accounts)
            storage_account, storage_secret = get_storage_credentials(path, storage)
            batch_account, region, aad_tenant, app_id, aad_secret = get_batch_credentials(path, batch)

            credential_dict = Dict{String, Any}(
                "_AD_TENANT" => aad_tenant,
                "_BATCH_ACCOUNT_NAME" => batch_account,
                "_REGION" => region,
                "_AD_BATCH_CLIENT_ID" => app_id,
                "_AD_SECRET_BATCH" => aad_secret,
                "_BATCH_ACCOUNT_URL" => join(["https://", batch_account, ".", region, ".batch.azure.com"]),
                "_BATCH_RESOURCE" => "https://batch.core.windows.net/",
                "_STORAGE_ACCOUNT_NAME" => storage_account,
                "_STORAGE_ACCOUNT_KEY" => storage_secret
            )
            push!(credentials, credential_dict)
        end
    elseif length(batch_accounts) == 1 && length(storage_accounts) >= 1

        batch_account, region, aad_tenant, app_id, aad_secret = get_batch_credentials(path, batch_accounts[1])
        for storage in storage_accounts
            storage_account, storage_secret = get_storage_credentials(path, storage)

            credential_dict = Dict{String, Any}(
                "_AD_TENANT" => aad_tenant,
                "_BATCH_ACCOUNT_NAME" => batch_account,
                "_REGION" => region,
                "_AD_BATCH_CLIENT_ID" => app_id,
                "_AD_SECRET_BATCH" => aad_secret,
                "_BATCH_ACCOUNT_URL" => join(["https://", batch_account, ".", region, ".batch.azure.com"]),
                "_BATCH_RESOURCE" => "https://batch.core.windows.net/",
                "_STORAGE_ACCOUNT_NAME" => storage_account,
                "_STORAGE_ACCOUNT_KEY" => storage_secret
            )
            push!(credentials, credential_dict)
        end
    else
        throw("Need to provide at least one storage account per batch account.")
    end

    return credentials
end