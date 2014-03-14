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


# Global variables to be used across functions
ubuntu="Ubuntu"
centOS="CentOS"
suse="SUSE"

usrDir="/usr/local/"

# This function checks if Azure xplat-cli is already installed.
# If not, it will install it
function installAzureXplatCli() {
    
    azureModule=`which azure`

    if [ -z $azureModule ]
    then
        nodePath=`which node`
        echo "Azure xplat-cli is not installed. Installation will start..."
        
        # Check if Node.js is already installed. Else install it. This will also install 'npm' along with Node.js
        # This is required for installing Azure xplat-cli
        if [ -z $nodePath ]
        then
            echo "Node.js is not installed. Installation will start..."
			# Install wget if not already installed, before installing Node.js
			installWget
            installNodeJS
        else
            echo "Node.js is already installed"
        
            npmPath=`which npm`

            # If Node.js is installed, but npm is not installed, then install it.
            # This is required for installing Azure xplat-cli
            if [ -z $npmPath ]
            then
                echo "npm is not installed. Installation will start..."
				# Install wget if not already installed, before installing NPM
				installWget
                installNPM
            else
                echo "npm is already installed"
            fi
        fi
        
        echo "Installing Azure xplat-cli..."
        `sudo npm -g install azure-cli`
        # Certain Linux distros will work with 'sudo npm install' and certain will work with 'npm install'.
		if [ $? -gt 0 ]
        then
			# Provide access to current user to /usr/local directory.
			# This is required to install Azure xplat-cli using 'npm' command.			
			currentUser=$(whoami)
			sudo chown -R $currentUser $usrDir
            `npm -g install azure-cli`
        fi

    else
        echo "Azure xplat-cli is already installed"
    fi
}


# This function will install Node.js and npm module
function installNodeJS() {
    # Find out if the Linux Kernel is 32-bit or 64-bit
    # Accordingly, the Node.js tar should be downloaded from Nodejs.org
    linuxKernel=`getconf LONG_BIT`
    if [ $linuxKernel -ne 64 ]
    then
        linuxKernel=86
    fi

    nodeTar="node-v0.10.26-linux-x$linuxKernel.tar.gz"
    nodeUrl="http://nodejs.org/dist/v0.10.26/$nodeTar"
  
    nodeDir=$HOME/nodeJS

    # Remove the directory if it already exists and create a new one
    rm -rf $nodeDir
    mkdir $nodeDir
    cd $nodeDir
    
    wget $nodeUrl
    tar --strip-components=1 -zxf $nodeTar
    
    sudo cp bin/* $usrDir/bin
    sudo cp -R lib/* $usrDir/lib
    sudo cp -R share/* $usrDir/share
    
    # Remove the node directory in user's home directory after copying to /usr/local
    rm -r $nodeDir

    cd $usrDir/bin
    # Remove the copied file and create a symbolic link to npm
    sudo rm -r npm
    sudo ln -s ../lib/node_modules/npm/bin/npm-cli.js npm

    echo "Node.js version: `node -v`"
    echo "npm version: `npm -v`"
}


# This function will install the npm module if Node.js is already installed
function installNPM() {
    # Download the install.sh to the user's home directory
    wget -P $HOME  https://npmjs.org/install.sh
    
	# install.sh has a command which has input redirection from the terminal (/dev/tty). 
	# This will not work when the script is executed remotely, since there is no terminal. 
	# Replace it with /dev/null
	sed -i "s/\/dev\/tty/\/dev\/null/g" $HOME/install.sh
	
    sudo sh $HOME/install.sh
    
    # Remove the install.sh and tmp directory generated, after installing npm
    rm $HOME/install.sh
	rm -r $HOME/tmp
    
    echo "npm version: `npm -v`"
}

# This function will install the wget command. Depending on the type of OS, 
# the default package manager is used to install wget
function installWget() {
	wgetPath=`which wget`

	if [ -z $wgetPath ]
	then
		echo "wget is not installed. Installation will start..."
		os=$(identifyOS)

		if [ "$os" == "$ubuntu" ]
		then
			sudo apt-get -y install wget
		elif [ "$os" == "$centOS" ]
		then
			sudo yum -y install wget
		elif [ "$os" == "$suse" ]
		then
			sudo zypper --non-interactive install wget
		else
			exit
		fi
	else
		echo "wget is already installed"
	fi
}


# This function identifies if the Linux OS is a distribution of Ubuntu, CentOS or SUSE
function identifyOS() {
    if [ ! -z "$(cat /etc/*-release | grep -i $ubuntu | head -1)" ]
    then
        echo $ubuntu
    elif [ ! -z "$(cat /etc/*-release | grep -i $centOS | head -1)" ]
    then
        echo $centOS
    elif [ ! -z "$(cat /etc/*-release | grep -i $suse | head -1)" ]
    then
        echo $suse
    else
        echo "ERROR: OS not supported" >&2
        cat /etc/*-release >&2
        exit
    fi
}



# Install the Azure xplat-cli if it is not already installed. This is required to execute the 
# Azure Storage download commands
installAzureXplatCli

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
