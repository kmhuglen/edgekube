# edgekube

How to setup and prepare a Ubuntu VM with MiniKube and Azure Arc on a Hyper-V host.

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

## Install git using Chocolatey
```PowerShell
choco install git.install -yfd
```

## Clone this repo
```PowerShell
New-Item -Type Directory C:\Repos
Set-Location C:\Repos
git clone 
```


