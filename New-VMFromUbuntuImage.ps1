#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [string]$FQDN = $VMName,

    [Parameter(Mandatory = $true, ParameterSetName = 'RootPassword')]
    [string]$RootPassword,

    #[Parameter(Mandatory=$true, ParameterSetName='RootPublicKey')]
    [string]$RootPublicKey,

    [uint64]$VHDXSizeBytes,

    [int64]$MemoryStartupBytes = 1GB,

    [int64]$MemoryMaximumBytes = 2GB,

    [bool]$EnableDynamicMemory,

    [int64]$ProcessorCount = 2,

    [string]$SwitchName = 'SWITCH',

    [string]$MacAddress,

    [string]$IPAddress,

    [string]$Gateway,

    [string[]]$DnsAddresses = @('1.1.1.1', '1.0.0.1'),

    [string]$InterfaceName = 'eth0',

    #[Parameter(Mandatory=$false, ParameterSetName='RootPassword')]
    #[Parameter(Mandatory=$false, ParameterSetName='RootPublicKey')]
    #[Parameter(Mandatory=$true, ParameterSetName='EnableRouting')]
    [switch]$EnableRouting,

    #[Parameter(Mandatory=$false, ParameterSetName='RootPassword')]
    #[Parameter(Mandatory=$false, ParameterSetName='RootPublicKey')]
    #[Parameter(Mandatory=$true, ParameterSetName='EnableRouting')]
    [string]$SecondarySwitchName,

    [string]$SecondaryMacAddress,

    [string]$SecondaryIPAddress,

    [string]$SecondaryInterfaceName,

    [string]$LoopbackIPAddress,

    [bool]$InstallDocker,
    
    [bool]$InstallK3S,

    [bool]$InstallKubernetes,
    [bool]$InitializeKubernetesMasterNode,
    [string]$KubernetesPodNetworkCIDR,

    [bool]$InstallAzureArc,
    [string]$serviceprincipalid,
    [string]$serviceprincipalsecret,
    [string]$resourcegroup,
    [string]$tenantid,
    [string]$location,
    [string]$subscriptionid,
    [string]$workspaceName,
    [string]$workspaceresourceGroup,
    [string]$workspaceId,
    [string]$workspaceKey
)

$ErrorActionPreference = 'Stop'

function Normalize-MacAddress ([string]$value) {
    $value.`
        Replace('-', '').`
        Replace(':', '').`
        Insert(2, ':').Insert(5, ':').Insert(8, ':').Insert(11, ':').Insert(14, ':').`
        ToLowerInvariant()
}

# Get default VHD path (requires administrative privileges)
$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"
$metadataIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-metadata.iso"

# Convert cloud image to VHDX
Write-Host 'Creating VHDX from cloud .img image...'
$ErrorActionPreference = 'Continue'
& {
    & tools\qemu-img-win-x64\qemu-img.exe convert -f qcow2 $SourcePath -O vhdx -o subformat=dynamic $vhdxPath
    if ($LASTEXITCODE -ne 0) {
        throw "qemu-img returned $LASTEXITCODE. Aborting."
    }
}

$ErrorActionPreference = 'Stop'
if ($VHDXSizeBytes) {
    Resize-VHD -Path $vhdxPath -SizeBytes $VHDXSizeBytes
}

# Create VM
Write-Host 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $vhdxPath -SwitchName $SwitchName
$vm | Set-VMProcessor -Count $ProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
if ($EnableDynamicMemory) {
    $vm | Set-VMMemory -DynamicMemoryEnabled $true 
    $vm | Set-VMMemory -MaximumBytes $MemoryMaximumBytes
}
# Sets Secure Boot Template. 
#   Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' doesn't work anymore (!?).
$vm | Set-VMFirmware -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')

# Ubuntu 16.04/18.04 startup hangs without a serial port (!?) -- https://bit.ly/2AhsihL
$vm | Set-VMComPort -Number 2 -Path "\\.\pipe\dbg1"

# Setup first network adapter
if ($MacAddress) {
    $MacAddress = Normalize-MacAddress $MacAddress
    $vm | Set-VMNetworkAdapter -StaticMacAddress $MacAddress.Replace(':', '')
}
$eth0 = Get-VMNetworkAdapter -VMName $VMName 
$eth0 | Rename-VMNetworkAdapter -NewName $InterfaceName

if ($SecondarySwitchName) {
    # Add secondary network adapter
    $eth1 = Add-VMNetworkAdapter -VMName $VMName -Name $SecondaryInterfaceName -SwitchName $SecondarySwitchName -PassThru

    if ($SecondaryMacAddress) {
        $SecondaryMacAddress = Normalize-MacAddress $SecondaryMacAddress
        $eth1 | Set-VMNetworkAdapter -StaticMacAddress $SecondaryMacAddress.Replace(':', '')
    }
}

# Start VM just to create MAC Addresses
$vm | Start-VM
Start-Sleep -Seconds 1
$vm | Stop-VM -Force

# Wait for Mac Addresses
Write-Host "Waiting for MAC addresses..."
do {
    $eth0 = Get-VMNetworkAdapter -VMName $VMName -Name $InterfaceName
    $MacAddress = Normalize-MacAddress $eth0.MacAddress
    Start-Sleep -Seconds 1
} while ($MacAddress -eq '00:00:00:00:00:00')

if ($SecondarySwitchName) {
    do {
        $eth1 = Get-VMNetworkAdapter -VMName $VMName -Name $SecondaryInterfaceName
        $SecondaryMacAddress = Normalize-MacAddress $eth1.MacAddress
        Start-Sleep -Seconds 1
    } while ($SecondaryMacAddress -eq '00:00:00:00:00:00')
}

# Create metadata ISO image
#   Creates a NoCloud data source for cloud-init.
#   More info: http://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
Write-Host 'Creating metadata ISO image...'
$instanceId = [Guid]::NewGuid().ToString()
 
$metadata = @"
instance-id: $instanceId
local-hostname: $VMName
"@

$RouterMark = if ($EnableRouting) { '<->' } else { '   ' }
$IpForward = if ($EnableRouting) { 'IPForward=yes' } else { '' }
$IpMasquerade = if ($EnableRouting) { 'IPMasquerade=yes' } else { '' }
if ($SecondarySwitchName) {
    $DisplayInterfaces = "     $($InterfaceName): \4{$InterfaceName}  $RouterMark  $($SecondaryInterfaceName): \4{$SecondaryInterfaceName}"
}
else {
    $DisplayInterfaces = "     $($InterfaceName): \4{$InterfaceName}"
}

$sectionWriteFiles = @"
write_files:
 - content: |
     \S{PRETTY_NAME} \n \l

$DisplayInterfaces
     
   path: /etc/issue
   owner: root:root
   permissions: '0644'

 - content: |
     [Match]
     MACAddress=$MacAddress

     [Link]
     Name=$InterfaceName
   path: /etc/systemd/network/20-$InterfaceName.link
   owner: root:root
   permissions: '0644'

 - content: |
     # Please see /etc/systemd/network/ for current configuration.
     # 
     # systemd.network(5) was used directly to configure this system
     # due to limitations of netplan(5).
   path: /etc/netplan/README
   owner: root:root
   permissions: '0644'

"@

if ($IPAddress) {
    # eth0 (Static)

    # Fix for /32 addresses
    if ($IPAddress.EndsWith('/32')) {
        $RouteForSlash32 = @"

     [Route]
     Destination=0.0.0.0/0
     Gateway=$Gateway
     GatewayOnlink=true
"@
    }

    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$InterfaceName

     [Network]
     Address=$IPAddress
     Gateway=$Gateway
     DNS=$($DnsAddresses[0])
     DNS=$($DnsAddresses[1])
     $IpForward
     $RouteForSlash32
   path: /etc/systemd/network/20-$InterfaceName.network
   owner: root:root
   permissions: '0644'

"@
}
else {
    # eth0 (DHCP)
    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$InterfaceName

     [Network]
     DHCP=true
     $IpForward

     [DHCP]
     UseMTU=true
   path: /etc/systemd/network/20-$InterfaceName.network
   owner: root:root
   permissions: '0644'

"@
}

if ($SecondarySwitchName) {
    $sectionWriteFiles += @"
 - content: |
     [Match]
     MACAddress=$SecondaryMacAddress

     [Link]
     Name=$SecondaryInterfaceName
   path: /etc/systemd/network/20-$SecondaryInterfaceName.link
   owner: root:root
   permissions: '0644'

"@

    if ($SecondaryIPAddress) {
        # eth1 (Static)
        $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$SecondaryInterfaceName

     [Network]
     Address=$SecondaryIPAddress
     $IpForward
     $IpMasquerade
   path: /etc/systemd/network/20-$SecondaryInterfaceName.network
   owner: root:root
   permissions: '0644'

"@
    }
    else {
        # eth1 (DHCP)
        $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$SecondaryInterfaceName

     [Network]
     DHCP=true
     $IpForward
     $IpMasquerade

     [DHCP]
     UseMTU=true
   path: /etc/systemd/network/20-$SecondaryInterfaceName.network
   owner: root:root
   permissions: '0644'

"@
    }
}

if ($LoopbackIPAddress) {
    # lo
    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=lo

     [Network]
     Address=$LoopbackIPAddress
   path: /etc/systemd/network/20-lo.network
   owner: root:root
   permissions: '0644'

"@
}
    
$sectionRunCmd = @'
runcmd:
 - '#apt-get update'
 - 'rm /etc/netplan/50-cloud-init.yaml'
 - 'touch /etc/cloud/cloud-init.disabled'
 - '#sudo rm /boot/grub/menu.lst'
 - '#apt-get upgrade -y'
 - '#apt-get dist-upgrade -y'
 - 'update-grub'     # fix "error: no such device: root." -- https://bit.ly/2TBEdjl
 - 'sudo DEBIAN_FRONTEND=noninteractive apt-get -y install "linux-azure"'
'@

if ($RootPassword) {
    $sectionPasswd = @"
password: $RootPassword
chpasswd: { expire: False }
ssh_pwauth: True
"@
}
elseif ($RootPublicKey) {
    $sectionPasswd = @"
ssh_authorized_keys:
  - $RootPublicKey
"@
}

if ($InstallDocker) {
    $sectionRunCmd += @'

 - 'echo "####"'
 - 'echo "#### InstallDocker - START"'
 - 'echo "####"'
 - 'apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common'
 - 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -'
 - 'add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"'
 - 'apt update -y'
 - 'apt install -y docker-ce docker-ce-cli containerd.io docker-compose'
 - 'echo "#### InstallDocker - END"'
'@
}

if ($InstallKubernetes) {
    $sectionRunCmd += @"

 - 'echo "####"'
 - 'echo "#### InstallKubernetes - START"'
 - 'echo "####"'
 - '#sudo apt-get install curl'
 - 'curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add'
 - 'sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"'
 - 'apt update -y'
 - 'sudo apt-get install -y kubeadm kubelet kubectl'
 - 'sudo apt-mark -y hold kubeadm kubelet kubectl'
 - 'sudo swapoff -a'
 - 'sudo snap install helm --classic'
 - 'echo "#### InstallKubernetes - END"'
"@
}

if ($InitializeKubernetesMasterNode) {
    $sectionRunCmd += @"

 - 'echo "####"'
 - 'echo "#### InitializeKubernetesMasterNode - START"'
 - 'echo "####"'
 - 'kubeadm init --pod-network-cidr=$KubernetesPodNetworkCIDR'
 - 'mkdir -p /root/.kube'
 - 'mkdir -p /home/ubuntu/.kube'
 - 'cp -i /etc/kubernetes/admin.conf /root/.kube/config'
 - 'cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config'
 - 'chown 0:0 /root/.kube/config'
 - 'chown 1000:1000 /home/ubuntu/.kube/config'
 - 'kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml --kubeconfig=/etc/kubernetes/admin.conf'
 - 'kubectl get pods --all-namespaces --kubeconfig=/etc/kubernetes/admin.conf'
 - 'echo "#### InitializeKubernetesMasterNode - END"'
"@
}

if ($InstallAzureArc) {
    $sectionRunCMD += @"

 - 'echo "####"'
 - 'echo "#### InstallAzureArc - START"'
 - 'echo "####"'
 - 'wget https://aka.ms/azcmagent -O /home/ubuntu/install_linux_azcmagent.sh'
 - 'bash /home/ubuntu/install_linux_azcmagent.sh'
 - 'azcmagent connect --service-principal-id $serviceprincipalid --service-principal-secret $serviceprincipalsecret --resource-group $resourcegroup --tenant-id $tenantid --location $location --subscription-id $subscriptionid'
 - 'echo "##### Install Log Analytics Agents"'
 - 'curl -o onboard_agent.sh -L https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh'
 - 'sudo sh onboard_agent.sh -w $workspaceId -s $workspaceKey'
 - 'echo "#### InstallAzureArc - END"'
"@
}

if ($InstallAzureArc -and $InitializeKubernetesMasterNode) {
    $sectionRunCMD += @"

 - 'echo "####"'
 - 'echo "#### InstallAzureArc & InitializeKubernetesMasterNode - START"'
 - 'echo "####"'
 - 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
 - 'az login --service-principal -u $serviceprincipalid -p $serviceprincipalsecret --tenant $tenantid'
 - 'az extension add --name connectedk8s'
 - 'az extension add --name k8sconfiguration'
 - 'az config set extension.use_dynamic_install=yes_without_prompt'
 - 'az connectedk8s connect --name $VMName --resource-group $resourcegroup --kube-config=/etc/kubernetes/admin.conf'
 - 'kubectl get pods -n azure-arc --kubeconfig=/etc/kubernetes/admin.conf'
 - 'echo "#### InstallAzureArc & InitializeKubernetesMasterNode - END"'
"@
}

if ($InstallK3S) {
    $sectionRunCMD += @"

 - 'echo "####"'
 - 'echo "#### InstallK3S - START"'
 - 'echo "####"'
 - 'sudo mkdir /home/ubuntu/.kube'
 - 'sudo curl -sLS https://get.k3sup.dev | sh'
 - 'sudo cp k3sup /usr/local/bin/k3sup'
 - 'sudo k3sup install --local --user ubuntu --k3s-channel stable --merge --context k3s --local-path /home/ubuntu/.kube/config --k3s-extra-args "--no-deploy traefik --write-kubeconfig-mode 644"'
 - '#sudo chmod 644 /etc/rancher/k3s/k3s.yaml'
 - 'sudo kubectl get node -o wide'
 - 'echo "##### Installing Helm 3"'
 - 'sudo snap install helm --classic'
 - 'echo "#### InstallK3S - END"'
"@
}
if ($InstallAzureArc -and $InstallK3S) {
    $sectionRunCMD += @"

 - 'echo "####"'
 - 'echo "#### InstallAzureArc & InstallK3S - START"'
 - 'echo "####"'
 - 'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
 - 'az login --service-principal -u $serviceprincipalid -p $serviceprincipalsecret --tenant $tenantid'
 - 'az config set extension.use_dynamic_install=yes_without_prompt'
 - 'az connectedk8s connect --name $VMName --resource-group $resourcegroup --kube-config=/home/ubuntu/.kube/config'
 - 'sudo kubectl get pods -n azure-arc --kubeconfig=/home/ubuntu/.kube/config'
 - 'echo "##### Enable Monitoring"'
 - 'curl -o enable-monitoring.sh -L https://aka.ms/enable-monitoring-bash-script'
 - 'sudo bash enable-monitoring.sh --resource-id "/subscriptions/$subscriptionid/resourceGroups/$resourcegroup/providers/Microsoft.Kubernetes/connectedClusters/$VMname" --client-id $serviceprincipalid --client-secret $serviceprincipalsecret --tenant-id $tenantid --kube-context default --workspace-id "/subscriptions/$subscriptionid/resourceGroups/$workspaceresourceGroup/providers/microsoft.operationalinsights/workspaces/$workspaceName"'
 - 'echo "#### InstallAzureArc & InstallK3S - END"'
"@
}

$Upgrade = $false
if ($Upgrade) {
    $sectionRunCMD += @"

 - 'echo "####"'
 - 'echo "#### Upgrade - START"'
 - 'echo "####"'
 - '#echo "rm /boot/grub/menu.lst"'
 - '#sudo rm /boot/grub/menu.lst'
 - '#apt-get upgrade -y'
 - '#apt-get dist-upgrade -y'
 - '#echo "apt-get install "linux-azure" -y"'
 - '#apt-get install "linux-azure" -y'
 - 'echo "#### Upgrade - END"'
"@
}

$userdata = @"
#cloud-config
hostname: $FQDN
fqdn: $FQDN

$sectionPasswd
$sectionWriteFiles
$sectionRunCmd

power_state:
  mode: reboot
  timeout: 120
"@

# Uses netplan to setup first network interface on first boot (due to cloud-init).
#   Then erase netplan and uses systemd-network for everything.
if ($IPAddress) {
    # Fix for /32 addresses
    if ($IPAddress.EndsWith('/32')) {
        $RouteForSlash32 = @"

    routes:
      - to: 0.0.0.0/0
        via: $Gateway
        on-link: true
"@
    }

    $NetworkConfig = @"
version: 2
ethernets:
  eth0:
    addresses: [$IPAddress]
    gateway4: $Gateway
    nameservers:
      addresses: [$($DnsAddresses -join ', ')]
    $RouteForSlash32
"@
}
else {
    $NetworkConfig = @"
version: 2
ethernets:
  eth0:
    dhcp4: true
"@
}

# Save all files in temp folder and create metadata .iso from it
Write-Host 'Save all files in temp folder and create metadata .iso from it'
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $instanceId
mkdir $tempPath | Out-Null
try {
    $metadata | Out-File "$tempPath\meta-data" -Encoding ascii
    $userdata | Out-File "$tempPath\user-data" -Encoding ascii
    $NetworkConfig | Out-File "$tempPath\network-config" -Encoding ascii

    $oscdimgPath = Join-Path $PSScriptRoot '.\tools\oscdimg.exe'
    & {
        $ErrorActionPreference = 'Continue'
        & $oscdimgPath $tempPath $metadataIso -j2 -lcidata
        if ($LASTEXITCODE -gt 0) {
            throw "oscdimg.exe returned $LASTEXITCODE."
        }
    }
}
finally {
    rmdir -Path $tempPath -Recurse -Force
    $ErrorActionPreference = 'Stop'
}

# Adds DVD with metadata.iso
Write-Host 'Add DVD and metadata.iso'
$dvd = $vm | Add-VMDvdDrive -Path $metadataIso -Passthru

# Disable Automatic Checkpoints. Check if command is available since it doesn't exist in Server 2016.
$command = Get-Command Set-VM
if ($command.Parameters.AutomaticCheckpointsEnabled) {
    Write-Host 'Disable Automatic VM Checkpoints'
    $vm | Set-VM -AutomaticCheckpointsEnabled $false
}

# Wait for VM
$vm | Start-VM
Write-Host 'Waiting for VM integration services (1)...'
Wait-VM -Name $VMName -For Heartbeat

# Cloud-init will reboot after initial machine setup. Wait for it...
Write-Host 'Waiting for VM initial setup...'
try {
    Wait-VM -Name $VMName -For Reboot
}
catch {
    # Win 2016 RTM doesn't have "Reboot" in WaitForVMTypes type. 
    #   Wait until heartbeat service stops responding.
    $heartbeatService = ($vm | Get-VMIntegrationService -Name 'Heartbeat')
    while ($heartbeatService.PrimaryStatusDescription -eq 'OK') { Start-Sleep  1 }
}

Write-Host 'Waiting for VM integration services (2)...'
Wait-VM -Name $VMName -For Heartbeat

# Removes DVD and metadata.iso
Write-Host 'Removes DVD and metadata.iso'
$dvd | Remove-VMDvdDrive
$metadataIso | Remove-Item -Force

# Return the VM created.
Write-Host 'All done!'
$vm
