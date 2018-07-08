$params = @{
    FilePath = ".\binaries\packer.exe"
    ArgumentList = "build -var `"password=vcenterpassword`" -var `"winrm_password=localadminpassword`" `".\server-2016.json`""
}
 
Start-Process @params -NoNewWindow -Wait