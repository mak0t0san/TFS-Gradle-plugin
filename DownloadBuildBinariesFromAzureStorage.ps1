<#
.SYNOPSIS
    Copies Build binaries from Azure Storage Container to a local folder.

.DESCRIPTION
    Copies blobs from a single storage container to a local directory.  If the blobs 
	have "/" in the name to represent a directory hierarchy, then the script will 
	recreate that directory hierarchy under the local destination path specified.

.EXAMPLE
    .\DownloadBuildBinariesFromAzureStorage `
		-StorageAccountName <myStorageAccountName> -StorageAccountKey <myStorageAccountKey> `
		-ContainerName <myContainerName> -Destination "<myLocalPath>" `
		-SMTPServer <smtp.myserver.com> -SMTPPort <portNumber> `
		-EmailFrom <user@domain.com> -EmailTo "<user2@domain2.com, user3@domain.com>" `
		-SMTPUserName <username> -SMTPPassword <password>
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
	$Destination,
	
	# SMTP Server
	[Parameter(Mandatory = $true)]
	$SMTPServer,
	
	# SMTP Port
	[Parameter(Mandatory = $true)]
	$SMTPPort,
	
	# Email From Address
	[Parameter(Mandatory = $true)]
	$EmailFrom,
	
	# Email To Addresses, comma separated
	[Parameter(Mandatory = $true)]
	[string[]]$EmailTo,
	
    # SMTP User name
    [Parameter(Mandatory = $true)]	
	$SMTPUserName,
	
	# SMTP Password
    [Parameter(Mandatory = $true)]	
	$SMTPPassword
)

Try
{
	# Set the properties for emailing the status of download
	$Subject = "Download Build Binaries - Status" 
	$Body = "" 
	$SMTPClient = New-Object Net.Mail.SmtpClient($SMTPServer, $SMTPPort) 
	$SMTPClient.EnableSsl = $true 
	$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUserName, $SMTPPassword); 

	# Create the Azure Storage Context using the Account Name and Account Key
	$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

	# List the Azure Blobs in a given container and download each of the listed blobs to the destination folder
	Get-AzureStorageBlob -container $ContainerName -context $context | ForEach-Object {Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $_.Name -Force -Destination $Destination}
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
	$Body = "Error occurred while downloading Build Binaries!\nExcption Message: $ErrorMessage\nFailed Item: $FailedItem"
}
Finally
{
	# Send the email
	$SMTPClient.Send($EmailFrom, $EmailTo, $Subject, $Body)
}