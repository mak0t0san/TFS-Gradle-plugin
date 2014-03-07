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
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($CertToImport)
    $store.Close()

    <#
    $certCmd = 'CERTUTIL -addstore -enterprise -f -v root "' + $AzureManagementCertificate + '"'
    Invoke-Command -ScriptBlock {CERTUTIL -addstore -enterprise -f -v root "$AzureManagementCertificate"}
    #>
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

    $logFile = ($MyInvocation.MyCommand.Definition).Replace($MyInvocation.MyCommand.Name, "") + 'DeploymentScripts.log'
    $logFileContent =  "================================================================================================================================`n" `
                     + "                                 DEPLOYMENT SCRIPT EXECUTION FOR BUILD - `"" + $BlobNamePrefix + "`"                                        `n" `
                     + "================================================================================================================================`n"

    $WindowsOS = "Windows"
    $LinuxOS = "Linux"
    $DefaultHTTPSWinRMPort = "5986"
    $DefaultSSHPort = "22"
    $WindowsDownloadScript = "DownloadBuildBinariesFromAzureStorage.ps1"
    $LinuxDownloadScript = "DownloadBuildBinariesFromAzureStorage.sh"

    $cloudServieDNS = $CloudServiceName + ".cloudapp.net"


    # Import the Azure Management Certificate
    $logFileContent = $logFileContent + "Importing the Azure Management Certificate...... `n"
    $certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $AzureManagementCertificate
    # ImportCertificate $certToImport
    $logFileContent = $logFileContent + "......Imported the Azure Management Certificate `n"

    $mgmtCertThumbprint = $certToImport.Thumbprint


    # Use the 'Get Cloud Service Properties' Service Management REST API to get the details of 
    # all the VMs hosted in the Cloud Service
    $logFileContent = $logFileContent + "Get Cloud Service Properties `n"
    $reqHeaderDict = @{}
    $reqHeaderDict.Add('x-ms-version','2012-03-01') # API version
    $restURI = "https://management.core.windows.net/" + $SubscriptionId + "/services/hostedservices/" + $CloudServiceName + "?embed-detail=true"
    [xml]$cloudProperties = Invoke-RestMethod -Uri $restURI -CertificateThumbprint $mgmtCertThumbprint -Headers $reqHeaderDict 


    # Iterate through the Cloud Properties and get the details of each VM.
    # Depending on the OS (Windows or Linux), execute corresponding download scripts.
    $logFileContent = $logFileContent + "Iterate through the Cloud Service Properties `n"
    $cloudProperties.HostedService.Deployments.Deployment.RoleList.Role | foreach {
    
        $OS = $_.OSVirtualHardDisk.OS
        
        if ($OS -ieq $WindowsOS)
        {
            $logFileContent = $logFileContent `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ DEPLOYING TO " `
                                    + $WindowsOS + " VM : " + $_.RoleName `
                                    + " ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ `n"

            # Import the Cloud Service Certificate
            $logFileContent = $logFileContent + "Importing the Cloud Service Certificate...... `n"
            $certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $WinCertificate
            # ImportCertificate $certToImport
            $logFileContent = $logFileContent + "......Imported the Cloud Service Certificate `n"

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
                $securePassword = ConvertTo-SecureString $WinPassword
                $credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $VMUserName, $securePassword
            
                # Use the Skip CA Check option to avoid command failure, in case the certificate is not trusted
                $sessionOption = New-PSSessionOption -SkipCACheck
            
                Invoke-Command -ComputerName $cloudServieDNS -Credential $credential `
                    -InDisconnectedSession -SessionOption $sessionOption `
                    -UseSSL -Port $publicWinRMPort `
                    -FilePath $WindowsDownloadScript `
                    -ArgumentList $StorageAccountName, $StorageAccountKey, $StorageContainerName, $WinAppPath, $BlobNamePrefix
                    
                $logFileContent = $logFileContent `
                        + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ DEPLOYED TO " `
                        + $WindowsOS + " VM : " + $_.RoleName `
                        + " ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ `n"
            }
        }
        elseif ($OS -ieq $LinuxOS)
        {
            $logFileContent = $logFileContent `
                                    + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ DEPLOYING TO " `
                                    + $LinuxOS + " VM : " + $_.RoleName `
                                    + " ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ `n"

            $publicSSHPort = 0

            $_.Role.ConfigurationSets.ConfigurationSet.InputEndpoints | ForEach-Object {
                if ($_.InputEndpoint.LocalPort -eq $DefaultSSHPort)
                {
                    $publicSSHPort = $_.InputEndpoint.Port
                    break
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

                # TODO: trigger download script via ssh

                $logFileContent = $logFileContent `
                        + "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ DEPLOYED TO " `
                        + $LinuxOS + " VM : " + $_.RoleName `
                        + " ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ `n"
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
}
Finally
{
    # Log the details to log file
    $logFileContent >> $logFile
}