#!/bin/bash

# Store the original IFS (Internal Field Separator)
originalIFS=$IFS

# Validate the number of input arguments
if [ $# -ne 4 ]
then
    echo "Usage: $0 <storageAccountName> <storageAccountKey> <containerName> <destinationPath>"
    exit 2
fi

storageAccountName=$1
storageAccountKey=$2
containerName=$3
destination=$4

# Change the IFS to newline character (\n) so that each output line while listing blobs can be stored into an array
IFS=$'\n'

# List all the blobs in the container and get the name of the blobs into an array
blobNames=(`azure storage blob list --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --json | grep '"name":' | awk -F'"' '{print $4}'`)

# Restore the original TFS
IFS=$originalIFS

# Download each blob into the destination path. This will replace any files / folders with the same name, which may be already present in the destination path
for blob in "${blobNames[@]}"
do
    # Blob name and Destination Path should be enclosed in quotes as spaces may exist in the name
    azure storage blob download --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --blob "$blob" --destination "$destination" --quiet
done
