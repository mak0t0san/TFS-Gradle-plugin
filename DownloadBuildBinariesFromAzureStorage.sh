#!/bin/bash

# Store the original IFS (Internal Field Separator)
originalIFS=$IFS

if [ $# -ne 4 ]
then
    echo "Usage: $0 <storageAccountName> <storageAccountKey> <containerName> <destinationPath>"
    exit 2
fi

storageAccountName=$1
storageAccountKey=$2
containerName=$3
destination=$4

# Change the IFS to newline character (\n) so that each output line is store into the array blobList.
IFS=$'\n'

# List all the blobs in the container and get the name of the blobs into a list
blobList=(`azure storage blob list --account-name $storageAccountName --account-key $storageAccountKey --container $containerName | awk -F'(Block|Page)Blob' '{print $1}' | awk -F'    ' '{print $2}' | tail -n +5 | head -n -1 | sed 's/ *$//g'`)

# Restore the original TFS
IFS=$originalIFS

# Download each blob into the destination path. This will replace any files / folders with the same name already present in the destination path
for blob in "${blobList[@]}"
do
    azure storage blob download --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --blob "$blob" --destination "$destination" --quiet
done
