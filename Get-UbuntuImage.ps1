[CmdletBinding()]
param(
    [string]$OutputPath,
    [Parameter(Mandatory=$true)]
    [String]$Version = "18.04"
)

$ErrorActionPreference = 'Stop'

# Note: Github removed TLS 1.0 support. Enables TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol-bor 'Tls12'

if ($Version -eq "18.04-azure") {
    $urlRoot = 'https://cloud-images.ubuntu.com/releases/bionic/release/'
    $urlFile = 'ubuntu-18.04-server-cloudimg-amd64-azure.vhd.zip'
}
if ($Version -eq "18.04") {
    $urlRoot = 'https://cloud-images.ubuntu.com/releases/bionic/release/'
    $urlFile = 'ubuntu-18.04-server-cloudimg-amd64.img'
}
if ($Version -eq "20.04") {
    $urlRoot = 'https://cloud-images.ubuntu.com/releases/focal/release/'
    $urlFile = 'ubuntu-20.04-server-cloudimg-amd64.img'
}

$url = "$urlRoot/$urlFile"
        
if (-not $OutputPath) {
    $OutputPath = Get-Item '.\'
}

$imgFile = Join-Path $OutputPath $urlFile

if ([System.IO.File]::Exists($imgFile)) {
    Write-Host "File '$imgFile' already exists. Nothing to do."
} else {
    Write-Host "Downloading file '$imgFile'..."

    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $imgFile)

    Write-Host "Checking file integrity..."
    $sha1Hash = Get-FileHash $imgFile -Algorithm SHA1
    $allHashs = $client.DownloadString("$urlRoot/SHA1SUMS")
    $m = [regex]::Matches($allHashs, "(?<Hash>\w{40})\s\*$urlFile")
    if (-not $m[0]) { throw "Cannot get SHA1 hash for $urlFile." }
    $expectedHash = $m[0].Groups['Hash'].Value
    if ($sha1Hash.Hash -ne $expectedHash) { throw "Integrity check for '$imgFile' failed." }
}

$imgFile
