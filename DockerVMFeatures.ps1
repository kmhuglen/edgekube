Function Get-UbuntuCloudImage {
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )
    
    $ErrorActionPreference = 'Stop'
    
    # Enables TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
 
    $urlRoot = 'https://cloud-images.ubuntu.com/releases/focal/release/'
    $urlFile = 'ubuntu-20.04-server-cloudimg-amd64.img'
    
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
        $sha1Hash = Get-FileHash $imgFile -Algorithm SHA256
        $allHashs = $client.DownloadString("$urlRoot/SHA256SUMS")
        $m = [regex]::Matches($allHashs, "(?<Hash>\w{64})\s\*$urlFile")
        if (-not $m[0]) { throw "Cannot get hash for $urlFile." }
        $expectedHash = $m[0].Groups['Hash'].Value
        if ($sha1Hash.Hash -ne $expectedHash) { throw "Integrity check for '$imgFile' failed." }
    }
    
    $imgFile
}