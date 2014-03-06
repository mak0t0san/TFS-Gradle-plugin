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

$WinPassword >> 'logFile.txt'

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



# Import the Azure Management Certificate
$certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $AzureManagementCertificate
# ImportCertificate $certToImport


$mgmtCertThumbprint = $certToImport.Thumbprint
$cloudServieDNS = $CloudServiceName + ".cloudapp.net"


# Use the 'Get Cloud Service Properties' Service Management REST API to get the details of 
# all the VMs hosted in the Cloud Service
$reqHeaderDict = @{}
$reqHeaderDict.Add('x-ms-version','2012-03-01') # API version
$restURI = "https://management.core.windows.net/" + $SubscriptionId + "/services/hostedservices/" + $CloudServiceName + "?embed-detail=true"
[xml]$cloudProperties = Invoke-RestMethod -Uri $restURI -CertificateThumbprint $mgmtCertThumbprint -Headers $reqHeaderDict 


# Iterate through the Cloud Properties and get the details of each VM.
# Depending on the OS (Windows or Linux), execute corresponding download scripts.
$cloudProperties.HostedService.Deployments.Deployment.RoleList.Role | foreach {
    
    $OS = $_.OSVirtualHardDisk.OS

    if ($OS -ieq "Windows")
    {

        $publicWinRMPort = "0"

        $_.ConfigurationSets.ConfigurationSet.InputEndpoints.InputEndpoint | foreach {
            if ($_.LocalPort -eq "5986")
            {
                $publicWinRMPort = $_.Port                
            }
        }

        Write-Host "validating port...."

        if ($publicWinRMPort -eq "0")
        {
            # TODO: THROW ERROR - WinRM HTTPS Public Port not defined
        }
        else
        {
            Write-Host "validating port....done"

            # Import the VM Certificate
            $certToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $WinCertificate
            # ImportCertificate $certToImport

            Write-Host "Triggering download script...."
            $securePassword = ConvertTo-SecureString $WinPassword
            $credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $VMUserName, $securePassword
            $sessionOption = New-PSSessionOption -SkipCACheck
            Invoke-Command -ComputerName $cloudServieDNS -InDisconnectedSession `
                -Credential $credential -UseSSL -SessionOption $sessionOption `
                -FilePath DownloadBuildBinariesFromAzureStorage.ps1 `
                -ArgumentList $StorageAccountName, $StorageAccountKey, $StorageContainerName, $WinAppPath, $BlobNamePrefix
        }
    }
    elseif ($OS -ieq "Linux")
    {
        Write-Host $OS

        $publicSSHPort = 0

        $_.Role.ConfigurationSets.ConfigurationSet.InputEndpoints | ForEach-Object {
            if ($_.InputEndpoint.LocalPort -eq 22)
            {
                $publicSSHPort = $_.InputEndpoint.Port
                break
            }
        }

        if ($publicSSHPort -eq 0)
        {
            # TODO: THROW ERROR - SSH Public Port not defined
        }
        else
        {
            
        }
    }
    else
    {
        # TODO: THROW ERROR - OS not supported
    }
}
