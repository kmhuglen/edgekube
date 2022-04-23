# docker1

Run the following commands to set up docker1

```PowerShell
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/kmhuglen/edgekube/archive/refs/heads/main.zip -OutFile docker1.zip
Expand-Archive -Path docker1.zip .\
Set-Location .\edgekube-main
.\Get-Tools.ps1
.\Deploy-UbuntuVM.ps1 -ConfigFile .\config-docker1
```