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
	# Reset the error variable
	$error.clear()
	
	# Set the properties for emailing the status of download
	$emailSubject = "Download Build Binaries - Status" 
	$emailBody = "" 
	$SMTPClient = New-Object Net.Mail.SmtpClient($SMTPServer, $SMTPPort) 
	$SMTPClient.EnableSsl = $true 
	$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPUserName, $SMTPPassword); 

    function logAzureError ($errorObj)
    {
	    $errorMsg = $errorObj.InvocationInfo.InvocationName.ToString() + "  :  " + $errorObj.ToString() + "`n" `
					    + $errorObj.InvocationInfo.PositionMessage.ToString() + "`n" `
					    + "CategoryInfo  :  " + $errorObj.CategoryInfo.ToString() + "`n" `
					    + "FullyQualifiedErrorId  :  " + $errorObj.FullyQualifiedErrorId.ToString()
	
	    return $errorMsg
    }


	# Create the Azure Storage Context using the Account Name and Account Key
	$context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
	if ($error.Count -gt 0)
	{
		$emailSubject = "$emailSubject - ERROR!" 
		$emailBody = logAzureError $error[0]
	}
	else
	{
		# List the Azure Blobs in a given container
		$blobsList = Get-AzureStorageBlob -container $ContainerName -context $context 
		if ($error.Count -gt 0)
		{
			$emailSubject = "$emailSubject - ERROR!" 
			$emailBody = logAzureError $error[0]
		}
		else 
		{
			# Download each of the listed blobs to the destination folder
			foreach($blob in $blobsList)
			{
				$downloadResult = Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $blob.Name -Force -Destination $Destination
				if ($error.Count -gt 0)	
				{
					# NEED TO APPEND MULTIPLE ERRORS
                    $emailBody = logAzureError $error[0]
				}
                else
                {
                    # NEED TO FORMAT SUCCESS MESSAGE
                    $emailBody = $emailBody + "`n`n" + $downloadResult
                }
			}
            if ($error.Count -gt 0)	
            {
                $emailSubject = "$emailSubject - ERROR!" 
            }
            else
            {
                $emailSubject = "$emailSubject - SUCCESS" 
            }
		}
	}
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
	$emailSubject = "$emailSubject - ERROR!" 
	$emailBody = "Error occurred while downloading Build Binaries!`nException Message: $ErrorMessage`nFailed Item: $FailedItem"
}
Finally
{
	# Send the email
	$SMTPClient.Send($EmailFrom, $EmailTo, $emailSubject, $emailBody)
}