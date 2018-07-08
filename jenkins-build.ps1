<#
.SYNOPSIS
    Executes Packer within Jenkins
.DESCRIPTION
    Long description
.EXAMPLE
    & $ENV:Workspace\Path\To\Script\jenkins-build.ps1
.NOTES
    This script is to be executed from a jenkins job. Create 2 Secret files, each with user/password
    for both the vCenter acount and the Local Admin account within the VM. See
    https://support.cloudbees.com/hc/en-us/articles/203802500-Injecting-Secrets-into-Jenkins-Build-Jobs for more info.
    Update paths within the script
#>

$params = @{
    FilePath = "$ENV:WORKSPACE\binaries\packer.exe"
    ArgumentList = "build -var `"password=$($env:vCenterPassword)`" -var `"winrm_password=$($env:LocalAdminPassword)`" `"$($ENV:WORKSPACE)\server-2016-prod.json`""
    WorkingDirectory = "$ENV:WORKSPACE"
}
 
Start-Process @params -NoNewWindow -Wait