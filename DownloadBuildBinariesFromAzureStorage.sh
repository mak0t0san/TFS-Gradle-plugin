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


# Change the IFS to back quote (`) so that path names are split while executing awk by any other character
# ` is not allowed in a filename and hence can be used
IFS="\`"

# Get the destination's final directory name and path separately. Else there will be a problem specifying
# a directory path starting with / in the "azure storage blob download --destination" argument
destinationDir=(`echo "$destination" | awk -F "/" '{print $NF}'`)
destinationPath=(`echo "$destination" | awk -F "/$destinationDir" '{print $1}'`)

# Restore the original TFS
IFS=$originalIFS

# Change directory to the destination directory
cd $destinationPath

# Download each blob into the destination path. This will replace any files / folders with the same name, which may be already present in the destination path
for blob in "${blobNames[@]}"
do
    # Blob name and Destination Path should be enclosed in quotes as spaces may exist in the name
    azure storage blob download --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --blob "$blob" --destination "$destinationDir"  --quiet
done
