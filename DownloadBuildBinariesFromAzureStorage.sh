#!/bin/bash

# Redirect stdout ( > ) and stderr ( 2> ) to a log file under user's home directory
# Redirect the stdout and stderr streams using "tee" and a named pipe ( >() )
# Log file will be appended for subsequent runs
exec > >(tee -a $HOME/DownloadBuildBinariesFromAzureStorage.log)
exec 2> >(tee -a $HOME/DownloadBuildBinariesFromAzureStorage.log >&2)


# Validate the number of input arguments
if [ $# -ne 5 ]
then
    echo "Usage: $0 <storageAccountName> <storageAccountKey> <containerName> <blobNamePrefix> <destinationPath>" >&2
    exit 2
fi

storageAccountName=$1
storageAccountKey=$2
containerName=$3
blobNamePrefix=$4
destination=$5



echo "============================================================================================================================"
echo "                          DOWNLOAD STATUS FOR BUILD - $blobNamePrefix"
echo "============================================================================================================================"


function installNodeJS() {
    linuxKernel=`getconf LONG_BIT`
    if [ $linuxKernel -ne 64 ]
    then
        linuxKernel=86
    fi

    nodeTar="node-v0.10.26-linux-x$linuxKernel.tar.gz"
    nodeUrl="http://nodejs.org/dist/v0.10.26/$nodeTar"

	# nodeDir="/usr/local/bin/node"
#TEMP CODE.....
nodeDir=$HOME/node
rm -r $nodeDir

    mkdir $nodeDir
    cd $nodeDir

    wget $nodeUrl
    tar --strip-components=1 -zxf $nodeTar
    rm $nodeTar

#TEMP CODE.....
node -v
npm -v

    # Create symbolic links to node and npm
    ln -s $nodeDir/bin/node ..
    ln -s $nodeDir/lib/node_modules/npm/bin/npm-cli.js ../npm

    node -v
    npm -v
}

azureModule=`which azure`

if [ -z $azureModule ]
then

    nodePath=`which node`

    if [ -z $nodePath ]
    then
        echo "Node.js is not installed. Installation will start..."
        installNodeJS
    else
        echo "Node.js is already installed"

        npmPath=`which npm`

        if [ -z $npmPath ]
        then
            echo "npm is not installed. Installation will start..."
            installNodeJS
        else
            echo "npm is already installed"            
        fi
    fi
	
	`sudo npm -g install azure-cli`
else
    echo "Azure xplat-cli is already installed"
fi


# Store the original IFS (Internal Field Separator)
originalIFS=$IFS


# Change the IFS to newline character (\n) so that each output line while listing blobs can be stored into an array
IFS=$'\n'

# List all the blobs in the container and get the name of the blobs into an array
blobNames=(`azure storage blob list --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --prefix "$blobNamePrefix" --json | grep '"name":' | awk -F'"' '{print $4}'`)

# Restore the original TFS
IFS=$originalIFS


# Change the IFS to back quote ( ` ) so that path names are split while executing awk by any other character
# ` is not allowed in a filename and hence can be used
IFS="\`"

# Get the destination's final directory name and path separately. Else there will be a problem specifying
# a directory path starting with / in the "azure storage blob download --destination" argument
destinationDir=(`echo "$destination" | awk -F "/" '{print $NF}'`)
destinationPath=(`echo "$destination" | awk -F "/$destinationDir" '{if (NF > 1) print $1}'`)

# Restore the original TFS
IFS=$originalIFS

# Change directory to the destination directory
if [ ! -z "$destinationPath" ]
then
	cd $destinationPath
fi

# Download each blob into the destination path. This will replace any files / folders with the same name, 
# which may be already present in the destination path
for blob in "${blobNames[@]}"
do
    # Blob name and Destination Path should be enclosed in quotes as spaces may exist in the name
    azure storage blob download --account-name $storageAccountName --account-key $storageAccountKey --container $containerName --blob "$blob" --destination "$destinationDir"  --quiet
done
