# edgekube

How to setup and prepare a MiniKube on Hyper-V

## Prerequsite

* Windows Server 2019 Standard Edition with Hyper-V role

## Remote Powershell
```PowerShell
Enter-PSSession -ComputerName <fqdn of hyper-v server> -Cred (get-credential)
```

## Install Chocolatey 
```PowerShell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## Install git using Chocolatey
```PowerShell
choco install git
```

## Clone this repo
```PowerShell
New-Item -Type Directory C:\Repos
Set-Location C:\Repos
git clone 
```


