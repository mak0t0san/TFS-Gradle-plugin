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
		-BlobNamePrefix <blobNamePrefix>
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
	
	# The Blob Name Prefix of the blobs to be downloaded
	[Parameter(Mandatory = $true)]
	$BlobNamePrefix
)

function logAzureError ($errorObj)
{
	    $errorMsg = $errorObj.InvocationInfo.InvocationName.ToString() + "  :  " + $errorObj.ToString() + "`n" `
					    + $errorObj.InvocationInfo.PositionMessage.ToString() + "`n" `
					    + "CategoryInfo  :  " + $errorObj.CategoryInfo.ToString() + "`n" `
					    + "FullyQualifiedErrorId  :  " + $errorObj.FullyQualifiedErrorId.ToString()
	
	    return $errorMsg
}
	
Try
{
	# Reset the error variable
	$error.clear()

    $cmdletError = ""	
	$continueScriipt = $false
	
	# Set the properties for logging the status of download
	$logFile = "C:\DownloadBuildBinariesFromAzureStorage.log" 
	$logFileContent =  "================================================================================================================================`n" `
					 + "                                 DOWNLOAD STATUS FOR BUILD - `"" + $BlobNamePrefix + "`"                                        `n" `
					 + "================================================================================================================================`n"

    $installLogOut = "C:\AzurePowerShellInstallOutput.log"
    $installLogErr = "C:\AzurePowerShellInstallError.log"

	# Check if Azure PowerShell module exists, else install it
	$azureCmdlet = Get-Module -ListAvailable -Name 'Azure'
	if ($azureCmdlet.Name -eq "Azure")
	{
		$logFileContent = $logFileContent + "Windows Azure PowerShell module is already available. `n"
		$continueScript = $true
	}
	else
	{
		$logFileContent = $logFileContent + "Windows Azure PowerShell is not installed. `n"
		
		# Check if Web PI Command exists, else install it so that Azure PowerShell can be installed through it
		Get-Command 'webpicmd'
		if ($error.Count -gt 0)
		{
			# Reset the error variable
 	        $error.clear()
					
			$logFileContent = $logFileContent + "Web PI Command does not exist. Installation will start.... `n"
			
			
			# Download and Install Web Platform Installer Command Line
			(new-object net.webclient).DownloadFile('http://download.microsoft.com/download/7/0/4/704CEB4C-9F42-4962-A2B0-5C84B0682C7A/WebPlatformInstaller_amd64_en-US.msi', 'C:\WebPICmd.msi')
			Start-Process -FilePath 'C:\WebPICmd.msi' -ArgumentList '/quiet' -PassThru | Wait-Process
            

            # Set the %PATH% environment variable from the system to the environment variable in the PowerShell session
            # Else, the updated %PATH% will not be available during the script run
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

			$logFileContent = $logFileContent + "....Web PI Command has been successfully installed. `n"
		}
		else
		{
			$logFileContent = $logFileContent + "Web PI Command is already installed. `n"
		}

		$logFileContent = $logFileContent + "Windows Azure PowerShell installation will start..... `n"
		
		# Install WindowsAzurePowerShell
		Start-Process 'webpicmd' -ArgumentList '/Install /AcceptEULA /Products:WindowsAzurePowershell' -NoNewWindow -PassThru | Wait-Process

		$logFileContent = $logFileContent + "....Windows Azure PowerShell has been successfully installed. `n"
		
		$continueScript = $true
	}	
	
	if ($continueScript)
	{
	
		$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath","Machine")

        # Load the Azure module
		Import-Module Azure
		
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
			# List the Azure Blobs matching the BlobNamePrefix
			$blobsList = Get-AzureStorageBlob -Container $ContainerName -Context $context -Prefix $BlobNamePrefix
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
					
					$downloadResult = Get-AzureStorageBlobContent -Container $ContainerName -Context $context -Blob $blob.Name -Destination $Destination -Force
					$cmdletError = ""

					if ($error.Count -gt 0)	
					{
						$cmdletError = logAzureError $error[0]

						$logFileContent = $logFileContent + "`n" `
											+ "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE START~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" `
											+ $cmdletError + "`n" `
											+ "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~FAILURE END~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n" 
						
						# Reset the error variable, else for all subsequent downloads, the previous error will be considered
						$error.clear()
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