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
		-BlobNameFilter <blobNameFilter>
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
	
	# Provide the starting string of the Blob Name which will be matched while downloading blobs
	[Parameter(Mandatory = $true)]
	$BlobNameFilter
)


Try
{
	# Reset the error variable
	$error.clear()

    $cmdletError = ""
	
	# Set the properties for logging the status of download
	$logFile = "C:\DownloadBuildBinariesFromAzureStorage.log" 
	$logFileContent =  "================================================================================================================================`n" `
					 + "                                 DOWNLOAD STATUS FOR BUILD - " + $BlobNameFilter + "                                            `n" `
					 + "================================================================================================================================`n"
 
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
	$cmdletError = ""
	
    if ($error.Count -gt 0)
	{
		$cmdletError = logAzureError $error[0]
		$logFileContent = $logFileContent + "`n" + $cmdletError
	}
	else
	{
        # List the Azure Blobs matching the BlobNameFilter
        $BlobNameFilter = $BlobNameFilter + "*"
		$blobsList = Get-AzureStorageBlob -container $ContainerName -context $context -Blob $BlobNameFilter
        $cmdletError = ""

		if ($error.Count -gt 0)
		{
			$cmdletError = logAzureError $error[0]
            $logFileContent = $logFileContent + "`n" + $cmdletError
		}
		else 
		{
			# Download each of the listed blobs to the destination folder
			foreach($blob in $blobsList)
			{
				
		        $downloadResult = Get-AzureStorageBlobContent -container $ContainerName -context $context -blob $blob.Name -Force -Destination $Destination
		        $cmdletError = ""

		        if ($error.Count -gt 0)	
		        {
			        $cmdletError = logAzureError $error[0]

			        $logFileContent = $logFileContent + "`n" `
								        + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE START~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" `
								        + $cmdletError + "`n" `
								        + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE END~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" 
		        }
		        else
		        {
			        $logFileContent = $logFileContent + "`n" `
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
	$logFileContent = $logFileContent + "`n" `
						+ "Error occurred while Downloading Build Binaries!`nException Message: $ErrorMessage`nFailed Item: $FailedItem"
}
Finally
{
    # Log the details to log file
	$logFileContent >> $logFile
}