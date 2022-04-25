# edgekube

Run the following commands to set up edgekube on a Hyper-V server

```PowerShell
# Download the repository and expand it to the current location
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/kmhuglen/edgekube/archive/refs/heads/main.zip -OutFile docker1.zip
Expand-Archive -Path docker1.zip .\
Set-Location .\edgekube-main

# Download needed tools
.\Get-Tools.ps1

# Deploy the VM
.\Deploy-UbuntuVM.ps1 -ConfigFile .\config-docker1
```