
<#
.SYNOPSIS
    Gets the details of all the VMs present in a Cloud Service and deploys the Build
    Binaries to the VMs by downloading from Azure Storage.

.DESCRIPTION
    Using the Cloud Service Name provided, the details of all the VMs hosted in it is
	obtained. Then, corresponding scripts for Windows and Linux VMs are executed, which
    will download the Build Binaries from Azure Storage to the local folders of the VMs.

    The Windows parameters and Linux parameters are optional. But either Windows / Linux
    set of parameters have to be provided. When the Cloud Service has both Windows and 
    Linux parameters, then both sets should be provided.
    
.EXAMPLE
    .\DeployToAzureVMs `
        -SubscriptionId "<myAzureSubscriptionId>" -AzureManagementCertificate "<managementCertificatePath>" `
        -CloudServiceName <myCloudServiceName> `
        -StorageAccountName <myStorageAccountName> -StorageAccountKey <myStorageAccountKey> `
        -StorageContainerName <myContainerName> -BlobNamePrefix "<blobNamePrefix>" `
        -VMUserName <vmUserName> `
		-WinPassword <winPassword> -WinCertificate "<winCertificatePath>" -WinAppPath "<winAppPath>" `
        -LinuxSSHKey "<linuxSSHKey>" -LinuxAppPath "<linuxAppPath>"
#>
param (
    # The Azure Subscription ID
    [Parameter(Mandatory = $true)]
    $SubscriptionId,

    # The Azure Management Certificate file
    [Parameter(Mandatory = $true)]
    $AzureManagementCertificate,

    # The Azure Cloud Service Name which hosts the VMs
    [Parameter(Mandatory = $true)]
    $CloudServiceName,

    # The Azure Storage Account Name where the Build Binaries exist
    [Parameter(Mandatory = $true)]
    $StorageAccountName,

    # The Azure Storage Account Key
    [Parameter(Mandatory = $true)]
    $StorageAccountKey,
	
	# The Azure Storage Container Name
    [Parameter(Mandatory = $true)]
    $StorageContainerName,

    # The Blob Name Prefix of the blobs to be downloaded
    [Parameter(Mandatory = $true)]
    $BlobNamePrefix,

    # The VM User Name for both Linux and Windows
    [Parameter(Mandatory = $true)]
    $VMUserName,

    # The Windows VM Password
    [Parameter(Mandatory = $false)]
    $WinPassword,

    # The SSL Certificate file to connect to Windows VM over HTTPS protocol
    [Parameter(Mandatory = $false)]
    $WinCertificate,

    # The Windows VM folder to which the Build Binaries will be deployed
    [Parameter(Mandatory = $false)]
    $WinAppPath,

    # The Linux VM directory to which the Build Binaries will be deployed
    [Parameter(Mandatory = $false)]
    $deploymentScriptsDir,

     # The SSH Key file to connect to Linux VM over SSH protocol
    [Parameter(Mandatory = $false)]
    $LinuxSSHKey,
     
    # The Linux VM directory to which the Build Binaries will be deployed
    [Parameter(Mandatory = $false)]
    $LinuxAppPath
)


# Import the Certificate to the Local Machine Trusted Store
function ImportCertificate($certToImport)
{
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "My", "CurrentUser"
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($CertToImport)
    $store.Close()
}


# Extract the error details from the $error object
function logError ($errorObj)
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

    $logFileContent =  "===========================================================================`n" `
                     + "                  DEPLOYMENT1 SCRIPT EXECUTION FOR BUILD - `"" + $BlobNamePrefix + "`"                   `n" `
                     + "===========================================================================`n"

    echo $logFileContent
    $logFileContent = '';
    $WindowsOS = "Windows"
    $LinuxOS = "Linux"
    $DefaultHTTPSWinRMPort = "5986"
    $DefaultSSHPort = "22"
    $WindowsDownloadScript =  $deploymentScriptsDir + "\DownloadBuildBinariesFromAzureStorage.ps1"
    $LinuxDownloadScript =  $deploymentScriptsDir + "\DownloadBuildBinariesFromAzureStorage.sh"
   #echo "deploymentScriptsDir"
   #echo $deploymentScriptsDir
    $cloudServieDNS = $CloudServiceName + ".cloudapp.net"
   
    $WinPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($WinPassword))

    # Form the variables for Windows VMs
    $securePassword =ConvertTo-SecureString -AsPlainText -Force -String $WinPassword

    $credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $VMUserName, $securePassword            
    # Use the Skip CA Check option to avoid command failure, in case the certificate is not trusted

    $sessionOption = New-PSSessionOption -SkipCACheck
    
    # Form the variables for Linux VMs
    $sshHost = $VMUserName + "@" + $cloudServieDNS
    
    # In case there are spaces, then they should be escaped with backslash (\) for the Linux Shell script input arguments
    $blobNamePrefixEscaped = $BlobNamePrefix -replace ' ', '\ '
    $linuxAppPathEscaped = $LinuxAppPath -replace ' ', '\ '

    #Import the Azure Management Certificate (Can be a path for which build agent service account should be accessible, by default it runs under service account)
    $logFileContent = $logFileContent + "Importing the Azure Management Certificate...... `n"
    $certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $AzureManagementCertificate
    ImportCertificate $certToImport
    $logFileContent = $logFileContent + "......Imported the Azure Management Certificate `n"
    $mgmtCertThumbprint = $certToImport.Thumbprint

    echo $logFileContent 
    $logFileContent = '';
    
    # Use the 'Get Cloud Service Properties' Service Management REST API to get the details of all the VMs hosted in the Cloud Service
    $logFileContent = $logFileContent + "Get Cloud Service Properties"

    $reqHeaderDict = @{}
    $reqHeaderDict.Add('x-ms-version','2012-03-01') # API version
    $restURI = "https://management.core.windows.net/" + $SubscriptionId + "/services/hostedservices/" + $CloudServiceName + "?embed-detail=true"
    [xml]$cloudProperties = Invoke-RestMethod -Uri $restURI -CertificateThumbprint $mgmtCertThumbprint -Headers $reqHeaderDict 

    echo $logFileContent 
    $logFileContent = '';

    # Iterate through the Cloud Properties and get the details of each VM.
    # Depending on the OS (Windows or Linux), execute corresponding download scripts.
    $logFileContent = $logFileContent + "Iterate through the Cloud Service Properties `n"
    $cloudProperties.HostedService.Deployments.Deployment.RoleList.Role | foreach {
    
        $OS = $_.OSVirtualHardDisk.OS
        
        if ($OS -ieq $WindowsOS)
        {
            $logFileContent = $logFileContent `
                                    + "~~~~~~~~~~~~~~ TRIGGERING DEPLOYMENT TO " `
                                    + $WindowsOS + " VM : " + $_.RoleName `
                                    + " ~~~~~~~~~~~~~~ `n"

            $publicWinRMPort = "0"

            $_.ConfigurationSets.ConfigurationSet.InputEndpoints.InputEndpoint | foreach {
                if ($_.LocalPort -eq $DefaultHTTPSWinRMPort)
                {
                    $publicWinRMPort = $_.Port                
                }
            }

            if ($publicWinRMPort -eq "0")
            {
                throw "ERROR: WinRM HTTPS Endpoint (Private port " `
                        + $DefaultHTTPSWinRMPort + ") not found for " `
                        + $WindowsOS + " VM : " + $_.RoleName 
            }
            else
            {
                $logFileContent = $logFileContent + "Remotely triggering the download script on the VM `n"
            #-InDisconnectedSession
                Invoke-Command -ComputerName $cloudServieDNS -Credential $credential `
                     -SessionOption $sessionOption `
                    -UseSSL -Port $publicWinRMPort `
                    -FilePath $WindowsDownloadScript `
                    -ArgumentList $StorageAccountName, $StorageAccountKey, $StorageContainerName, $WinAppPath, $BlobNamePrefix
                
                if ($error.Count -gt 0)
                {
                    $logFileContent = $logFileContent + "ERROR OCCURRED: While remotely triggering the download script on the VM `n"
                    
                    # Reset the error variable, so that subsequent cmdlet execution will not consider this error
                    $error.Clear()
                }

                $logFileContent = $logFileContent `
                        + "~~~~~~~~~~~~~~ TRIGGERED DEPLOYMENT TO " `
                        + $WindowsOS + " VM : " + $_.RoleName `
                        + " ~~~~~~~~~~~~~~ `n"
            }
        }
        elseif ($OS -ieq $LinuxOS)
        {
            $logFileContent = $logFileContent `
                                    + "~~~~~~~~~~~~~~ TRIGGERING DEPLOYMENT TO " `
                                    + $LinuxOS + " VM : " + $_.RoleName `
                                    + " ~~~~~~~~~~~~~~ `n"

            $publicSSHPort = 0

            $_.ConfigurationSets.ConfigurationSet.InputEndpoints.InputEndpoint | ForEach-Object {
                if ($_.LocalPort -eq $DefaultSSHPort)
                {
                    $publicSSHPort = $_.Port
                }
            }

            if ($publicSSHPort -eq 0)
            {
                throw "ERROR: SSH Endpoint (Private port " `
                        + $DefaultSSHPort + ") not found for " `
                        + $LinuxOS + " VM : " + $_.RoleName 
            }
            else
            {
                $logFileContent = $logFileContent + "Remotely triggering the download script on the VM `n"

                Start-Process cmd -ArgumentList "/c ssh -i '$LinuxSSHKey' -o StrictHostKeyChecking=no -p $publicSSHPort $sshHost bash -s < $LinuxDownloadScript $StorageAccountName $StorageAccountKey $StorageContainerName $blobNamePrefixEscaped $linuxAppPathEscaped" -NoNewWindow

                if ($error.Count -gt 0)
                {
                    $logFileContent = $logFileContent + "ERROR OCCURRED: While remotely triggering the download script on the VM `n"
                    
                    # Reset the error variable, so that subsequent cmdlet execution will not consider this error
                    $error.Clear()
                }

                $logFileContent = $logFileContent `
                        + "~~~~~~~~~~~~~~ TRIGGERED DEPLOYMENT TO " `
                        + $LinuxOS + " VM : " + $_.RoleName `
                        + " ~~~~~~~~~~~~~~ `n"
            }
        }
        else
        {
            throw "ERROR: " + $OS + " OS not supported!"
        }
    }

   
}
Catch
{
    $excpMsg = logError $_
    $logFileContent = $logFileContent + "`n" + $excpMsg + "`n"
    echo $logFileContent 
    $logFileContent = '';
}
Finally
{
    # Log the details to log file
    echo $logFileContent 
}