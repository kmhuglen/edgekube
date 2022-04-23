#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigPath
)

$VerbosePreference = "Continue"

### Read Configuration Parameters from configUbuntu.json
#$configPath = Join-Path $PSScriptRoot "configUbuntu.json"
$c = Get-Content $configPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$d = $c.DeploySettingsParameters
$p = $c.VMFromUbuntuImageParameters

### Recalulate Bytes strings into UInt64 values
[uint64]$p.VHDXSizeBytes = ($p.VHDXSizeBytes /1)
[uint64]$p.MemoryStartupBytes = ($p.MemoryStartupBytes /1)
[uint64]$p.MemoryMaximumBytes = ($p.MemoryMaximumBytes /1)

### Output the current Configuration
If($p)
{
    Write-Output " "
    Write-Host "Configuration loaded from $configpath"
    Write-Output " "
    Write-Host "Deployment Settings Parameters:"
    $d|Format-List
    Write-Host "VM Image Parameters:"
    $p|Format-List
} else {
    Write-Error -ErrorAction Stop "Could not read configuration file"
}

### Download Source Image if DownloadSourceIFNotFound is true
If(-NOT(Test-Path $p.SourcePath)){
    If ($d.DownloadSourceIFNotFound)
    {   
        Write-Warning "Source image not found. Downloading Source Image..."
        .\Get-UbuntuImage.ps1 -Version "18.04"
    }
    else {
        Write-Error -message "Source image not found" -ErrorAction Stop
    }
}

### Deploy a Unattended new VM with the config provided.
#.\New-VMFromUbuntuImage.ps1 -SourcePath $c.SourcePath -VMName $c.VMName -VHDXSizeBytes $c.VHDXSizeBytes -RootPassword $c.RootPassword -MemoryStartupBytes $c.MemoryStartupBytes -EnableDynamicMemory $c.EnableDynamicMemory -SwitchName $c.SwitchName -IPAddress $c.IPAddress -Gateway $c.Gateway
# Convert the PSCustomObject back to a hashtable
$paramhash = @{}
$p.psobject.properties | ForEach-Object { $paramhash[$_.Name] = $_.Value }
.\New-VMFromUbuntuImage.ps1 @paramhash
