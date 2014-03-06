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
        -ContainerName <myContainerName> -BlobNamePrefix "<blobNamePrefix>" `
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
    $ContainerName,

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



# Import the Azure Management Certificate
$CertToImport = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $AzureManagementCertificate
$mgmtCertThumbprint = $CertToImport.Thumbprint
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
$store.Add($CertToImport)
$store.Close()


# Use the Get Cloud Service Properties Service Management REST API to get the details of all the
# VMs hosted in the Cloud Service
$reqHeaderDict = @{}
$reqHeaderDict.Add('x-ms-version','2012-03-01') # API version
$restURI = "https://management.core.windows.net/" + $SubscriptionId + "/services/hostedservices/" + $CloudServiceName + "?embed-detail=true"

[xml]$cloudPropXML = Invoke-RestMethod -Uri $restURI -CertificateThumbprint $mgmtCertThumbprint -Headers $reqHeaderDict 

# TEMP CODE
Write-Host $cloudPropXML.HostedService.ServiceName

