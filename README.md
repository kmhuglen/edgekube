# docker1

How to setup and prepare a Ubuntu VM with Docker on a Hyper-V host.

## Prerequsite

* Windows 10 or Windows Server 2019 or later with Hyper-V role

## Remote Powershell
(skip if working locally on your Windows 10 machine)

```PowerShell
Enter-PSSession -ComputerName <fqdn of hyper-v host> -Cred (get-credential)
```

## Install Chocolatey
```PowerShell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## Install Git using Chocolatey
```PowerShell
choco install git --params='/NoShellIntegration' -y
$env:path+='C:\Program Files\Git\cmd'
refreshenv
```

## Install GitPosh
```
Install-Module posh-git -Force
Import-Module posh-git
Add-PoshGitToProfile -AllHosts
```

## Clone this repo
```PowerShell
New-Item -Type Directory C:\Repos
Set-Location C:\Repos
git clone https://github.com/kmhuglen/edgekube.git
Set-Location C:\Repos\edgekube
```

## Deploy docker1

This is just an example. Modify config-docker1.json to fit your environment

```PowerShell
.\Deploy-UbuntuVM.ps1 -ConfigFile config-docker1.json
```
