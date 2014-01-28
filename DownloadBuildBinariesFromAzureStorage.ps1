<#
.SYNOPSIS
    Copies Build binaries from Azure Storage Container to a local folder.

.DESCRIPTION
    Copies blobs from a single storage container to a local directory.  If the blobs 
	have "/" in the name to represent a directory hierarchy, then the script will 
	recreate that directory hierarchy under the local destination path specified.

.EXAMPLE
    .\DownloadBuildBinariesFromAzureStorage `
		-StorageAccountName 'myStorageAccountName' -StorageAccountKey myStorageAccountKey `
		-ContainerName 'myContainerName' -Destination 'myLocalPath'
#>
param (
	# The Azure Storage Account Name where the Build Binaries exist
    [Parameter(Mandatory = $true)]
	$StorageAccountName,
	
	# The Azure Storage Account Key
	[Parameter(Mandatory = $true)]
    $StorageAccountKey,
	
	# The Azure Storage Container Name
	[Parameter(Mandatory = $true)]
	$ContainerName,
	
	# The Destination Path on the VM
	[Parameter(Mandatory = $true)]
	$Destination
)


# Create the Azure Storage Context using the Account Name and Account Key
$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

# List the Azure Blobs in a given container and download each of the listed blobs to the destination folder
Get-AzureStorageBlob -container $ContainerName -context $context | ForEach-Object {Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $_.Name -Force -Destination $Destination}


