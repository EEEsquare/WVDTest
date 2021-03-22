# These are some parameters for the dc deployment
$credential = Get-Credential -Message "Your VM Admin" -UserName 'wvdadmin'
$templateParameterObject1 = @{
'vmName' =  [string] 'JustComma-AD-VM1'
'adminUser'= [string] $($credential.UserName)
'adminPassword' = [securestring]$($credential.Password)
'vmSize'=[string] 'Standard_F2s'
'DiskSku' = [string] 'StandardSSD_LRS'
'DomainName' = [string] 'JustComma.local'
}

$deploymentstart = Get-Date

#Deploy the network
New-AzResourceGroupDeployment -ResourceGroupName 'rg-JustComma-basics' -Name 'NetworkSetup' -Mode Incremental -TemplateUri 'https://raw.githubusercontent.com/bfrankMS/wvdsandbox/master/BaseSetupArtefacts/01-ARM_Network.json'

#Deploy the VM and make it a domain controller
New-AzResourceGroupDeployment -ResourceGroupName 'rg-JustComma-basics' -Name 'DCSetup' -Mode Incremental -TemplateUri 'https://raw.githubusercontent.com/bfrankMS/wvdsandbox/master/BaseSetupArtefacts/02-ARM_AD.json' -TemplateParameterObject $templateParameterObject1

#make sure DC is new DNS server in this VNET  
az network vnet update -g 'rg-JustComma-basics' -n 'JustComma-vnet' --dns-servers 10.0.0.4 

#Restart the DC
Restart-AzVM -Name $($templateParameterObject1.vmName) -ResourceGroupName 'rg-JustComma-basics'

#wait for domain services to come online they may take a while to start up so query the service from within the vm.
$tempFile = "AzVMRunCommand"+ $("{0:D4}" -f (Get-Random -Maximum 9999))+".tmp.ps1"

$code = @"
    if (`$(Get-Service ADWS).Status -eq 'Running'){
    "ADWS is Running"
    }
"@
$code | Out-File $tempFile    #write this Powershell code into a local file 

do
{
    $result = Invoke-AzVMRunCommand -ResourceGroupName 'rg-JustComma-basics' -Name $($templateParameterObject1.vmName)  -CommandId 'RunPowerShellScript' -ScriptPath $tempFile
    Start-Sleep -Seconds 30
}
until ($result.Value.Message -contains "ADWS is Running")


# These are some parameters for the File Server deployment
$templateParameterObject2 = @{
'vmName' =  [string] 'JustComma-FS-VM1'
'adminUser'= [string] $($credential.UserName)
'adminPassword' = [securestring]$($credential.Password)
'vmSize'=[string] 'Standard_F2s'
'DiskSku' = [string] 'StandardSSD_LRS'
'DomainName' = [string] 'JustComma.local'
}
New-AzResourceGroupDeployment -ResourceGroupName 'rg-JustComma-basics' -Name 'FileServerSetup' -Mode Incremental -TemplateUri 'https://raw.githubusercontent.com/bfrankMS/wvdsandbox/master/BaseSetupArtefacts/03-ARM_FS.json' -TemplateParameterObject $templateParameterObject2

#cleanup: remove 'DCInstall' extension
Remove-AzVMCustomScriptExtension -Name 'DCInstall' -VMName $($templateParameterObject1.vmName) -ResourceGroupName 'rg-JustComma-basics' -Force  

#Do post AD installation steps: e.g. create OUs and some WVD Demo Users.
Set-AzVMCustomScriptExtension -Name 'PostDCActions' -VMName $($templateParameterObject1.vmName) -ResourceGroupName 'rg-JustComma-basics' -Location (Get-AzVM -ResourceGroupName 'rg-JustComma-basics' -Name $($templateParameterObject1.vmName)).Location -Run 'CSE_AD_Post.ps1' -Argument "WVD $($credential.GetNetworkCredential().Password)" -FileUri 'https://raw.githubusercontent.com/bfrankMS/wvdsandbox/master/BaseSetupArtefacts/CSE_AD_Post.ps1'  
  
#Cleanup
Remove-AzVMCustomScriptExtension -Name 'PostDCActions' -VMName $($templateParameterObject1.vmName) -ResourceGroupName 'rg-JustComma-basics' -Force -NoWait

# make this server a file server.
Set-AzVMCustomScriptExtension -Name 'FileServerInstall' -VMName $($templateParameterObject2.vmName) -ResourceGroupName 'rg-JustComma-basics' -Location (Get-AzVM -ResourceGroupName 'rg-JustComma-basics' -Name $($templateParameterObject2.vmName)).Location -Run 'CSE_FS.ps1' -FileUri 'https://raw.githubusercontent.com/bfrankMS/wvdsandbox/master/BaseSetupArtefacts/CSE_FS.ps1' 

#Cleanup
Remove-AzVMCustomScriptExtension -Name 'FileServerInstall' -VMName $($templateParameterObject2.vmName) -ResourceGroupName 'rg-JustComma-basics' -Force -NoWait  
  
#done :-)
"Hey you are done - your deployment took:{0}" -f  $(NEW-TIMESPAN –Start $deploymentstart –End $(Get-Date)).ToString("hh\:mm\:ss")  
  