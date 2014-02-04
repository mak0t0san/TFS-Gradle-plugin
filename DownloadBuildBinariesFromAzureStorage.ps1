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
    $errorFlag = $false

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
		$errorFlag = $true
		$emailBody = logAzureError $error[0]
	}
	else
	{
		# List the Azure Blobs in a given container
		$blobsList = Get-AzureStorageBlob -container $ContainerName -context $context 
		if ($error.Count -gt 0)
		{
			$errorFlag = $true
			$emailBody = logAzureError $error[0]
		}
		else 
		{
			# Download each of the listed blobs to the destination folder
			foreach($blob in $blobsList)
			{
				$downloadResult = Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $blob.Name -Force -Destination $Destination
                $downloadError = ""
				if ($error.Count -gt 0)	
				{
                    $errorFlag = $true

                    $downloadError = logAzureError $error[0]

                    $emailBody = $emailBody + "`n" `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE START~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" `
                                    + $downloadError + "`n" `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE END~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" 
                    
                    # Reset the error variable, else for all subsequent downloads, the previous error will be considered
	                $error.clear()
				}
                else
                {
                    $emailBody = $emailBody + "`n" `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SUCCESS START~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" `
                                    + "AbsoluteUri  : " + $downloadResult.ICloudBlob.Uri.AbsoluteUri + "`n" `
                                    + "Blob Name    : " + $downloadResult.Name + "`n" `
                                    + "Blob Type    : " + $downloadResult.BlobType + "`n" `
                                    + "Length       : " + $downloadResult.Length + "`n" `
                                    + "ContentType  : " + $downloadResult.ContentType + "`n" `
                                    + "LastModified : " + $downloadResult.LastModified.UtcDateTime + "`n" `
                                    + "SnapshotTime : " + $downloadResult.SnapshotTime + "`n" `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SUCCESS END~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
                }
			}
		}
	}
}
Catch
{
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
	$errorFlag = $true
	$emailBody = "Error occurred while Downloading Build Binaries!`nException Message: $ErrorMessage`nFailed Item: $FailedItem"
}
Finally
{
	if ($errorFlag -eq $true)
    {
        $emailSubject = "$emailSubject - ERROR!" 
    }
    else
    {
        $emailSubject = "$emailSubject - SUCCESS" 
    }

    # Send the email
	$SMTPClient.Send($EmailFrom, $EmailTo, $emailSubject, $emailBody)
}