# edgekube

Run the following commands to set up edgekube on a Hyper-V server

```PowerShell
# Download repository and tools
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/kmhuglen/edgekube/archive/refs/heads/main.zip -OutFile edgekube-main.zip ; Expand-Archive -Path edgekube-main.zip .\ -Force ; Remove-Item .\edgekube-main.zip ; Set-Location .\edgekube-main ; .\Get-Tools.ps1

# Deploy the VM
.\Deploy-UbuntuVM.ps1 -ConfigFile .\config-docker1
```