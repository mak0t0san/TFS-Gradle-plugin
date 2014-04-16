<#

Important

Get-AzurePublishSettingsFile
Import-AzurePublishSettingsFile
Get-AzureSubscription

winrm quickconfig
winrm set winrm/config/client/auth '@{Basic="true"}'
winrm set winrm/config/client '@{TrustedHosts="shal-win-service.cloudapp.net"}'
set-executionpolicy unrestricted
$CloudServiceName = 'WinVM-service'
$WinRMCert = (Get-AzureVM -ServiceName $CloudServiceName | select -ExpandProperty vm).DefaultWinRMCertificateThumbprint
$vm.VM.DefaultWinRMCertificateThumbprint

$WinRMCert.VM.DefaultWinRMCertificateThumbprint
$AzureX509cert = Get-AzureCertificate -ServiceName $CloudServiceName -Thumbprint $WinRMCert -ThumbprintAlgorithm sha1

$certFile = 'C:\Thiru\Certificate\VMCert.crt'
$AzureX509cert.Data | Out-File $certFile

And check to list all C: drive
$sessionOption = New-PSSessionOption –SkipCACheck 
$securePassword = ConvertTo-SecureString -AsPlainText -Force -String 'virtual@M'
$credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist 'azureuser', $securePassword
Invoke-Command -ComputerName 'shal-win-service.cloudapp.net' -Credential $credential -ScriptBlock {Get-ChildItem C:\} –UseSSL –SessionOption $sessionOption –Port 5986

Click the certificate and install
#>

#winrm quickconfig -transport:https
#netsh firewall add portopening TCP 5986 "WinRM over HTTPS"
#winrm set winrm/config/auth '@{basic=true}'
#winrm set winrm/config/client '@{TrustedHosts="138.91.38.167"}'
#Enable-WSManCredSSP -Role Client -DelegateComputer shal-win-service.cloudapp.net
#Enable-WSManCredSSP -Role Server
#set-executionpolicy unrestricted
#configure-SMremoting.ps1 -force -enable
#set-executionpolicy 
#set-executionpolicy remotesigned
#enable-psremoting
#$psversiontable
