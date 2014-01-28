<#
.SYNOPSIS
    Copies Build binaries from Azure Storage Container to a local folder on the
	Azure Windows VM.

.DESCRIPTION
    Copies blobs from a single storage container to a local directory.  If the blobs 
	have "/" in the name to represent a directory hierarchy, then the script will 
	recreate that directory hierarchy under the local destination path specified.

.EXAMPLE
    .\DownloadBuildBinariesFromAzureStorage -VMDNS 'vm-dns.cloudapp.net' `
        -UserName 'myUserName' -Password 'myPassword' `
		-StorageAccountName 'myStorageAccountName' -StorageAccountKey myStorageAccountKey `
		-ContainerName 'myContainerName' -Destination 'myLocalPath'
#>
param (
	# The DNS of the Azure Cloud Service where the Windows VM is deployed
    [Parameter(Mandatory = $true)]
	$VMDNS,
	
    # The User Name to connect to the VM
    [Parameter(Mandatory = $true)]
	$UserName,
	
    # The Password to connect to the VM
    [Parameter(Mandatory = $true)]
	$Password,
	
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


# Create the Remote Session
$securePassword = ConvertTo-SecureString -AsPlainText -Force -String $Password
$credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $UserName, $securePassword
$session  = New-PSSession -ComputerName $VMDNS -Credential $credential

$downloadBuildOutput = {
	param($StorageAccountName, $StorageAccountKey, $ContainerName, $Destination)

	$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

	Get-AzureStorageBlob -container $ContainerName -context $context | ForEach-Object {Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $_.Name -Force -Destination $Destination}
}

Invoke-Command -Session $session $downloadBuildOutput -ArgumentList  $StorageAccountName, $StorageAccountKey, $ContainerName, $Destination

# Remove the remote session
Remove-PSSession -Session $session