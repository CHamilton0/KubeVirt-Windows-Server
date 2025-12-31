$marker = "C:\kubevirt_init.done"

$computer_name = "DC-Root"
$ip_address = "192.168.10.10"
$dns_address = "192.168.10.10"
$SecureAdminPass = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
$domain_name = "example.local"
$domain_netbios_name = "EXAMPLE"

Rename-Computer -NewName $computer_name

$interface = (Get-NetAdapter | Where-Object Status -eq "Up")[0].Name
New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_address -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias $interface -ServerAddresses $dns_address

Set-LocalUser -Name Administrator -Password $SecureAdminPass

if (Test-Path $marker) {
    Write-Host "Already initialized"
    exit 0
}

Start-Transcript -Path C:\kubevirt_init.ps1.log -Append

# Wait for network
$timeout = 300
$elapsed = 0
while (-not (Get-NetAdapter | Where-Object Status -eq Up)) {
    Start-Sleep 5
    $elapsed += 5
    if ($elapsed -gt $timeout) {
        throw "Network never came up"
    }
}

Write-Host "Setting up post-reboot script"


$postRebootScript = @'
# Commands to run after reboot
Write-Host "Running post-reboot tasks..."

Import-Module ActiveDirectory

# Sites
$sites = @("RootSite","Site1","Site2")
foreach ($site in $sites) {
    if (-not (Get-ADReplicationSite -Filter "Name -eq '$site'")) {
        New-ADReplicationSite -Name $site
        Write-Host "Created site: $site"
    } else {
        Write-Host "Site $site already exists"
    }
}


$subnets = @(
    @{Subnet="192.168.10.0/24"; Site="RootSite"},
    @{Subnet="192.168.10.0/24"; Site="Site1"},
    @{Subnet="192.168.10.0/24"; Site="Site2"}
)

foreach ($s in $subnets) {
    if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$($s.Subnet)'")) {
        New-ADReplicationSubnet -Name $s.Subnet -Site $s.Site
        Write-Host "Created subnet $($s.Subnet) assigned to site $($s.Site)"
    } else {
        Write-Host "Subnet $($s.Subnet) already exists"
    }
}


$DCs = Get-ADDomainController -Filter *

foreach ($dc in $DCs) {
    switch ($dc.Name) {
        "DC-Root"   { $siteName = "RootSite" }
        "DC-Site1" { $siteName = "Site1" }
        "DC-Site2" { $siteName = "Site2" }
        default     { $siteName = "RootSite" }
    }

    if ($dc.Site -ne $siteName) {
        Move-ADDirectoryServer -Identity $dc.Name -Site $siteName
        Write-Host "Moved $($dc.Name) to site $siteName"
    } else {
        Write-Host "$($dc.Name) is already in $siteName"
    }
}

# Clean up this script
Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PostRebootSetup" -ErrorAction SilentlyContinue
'@

# Save post-reboot script
$postRebootScript | Out-File -FilePath "C:\Windows\Setup\Scripts\post-reboot.ps1" -Encoding UTF8

# Register to run once after reboot
$runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\post-reboot.ps1"
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PostRebootSetup" -Value $runOnceCommand

Write-Host "Configuring as Domain Controller..."

# Non-interactive feature install
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Confirm:$false -Restart:$false

# Reliable DC detection
Write-Host "Starting AD forest creation (will reboot)"
Install-ADDSForest `
    -DomainName $domain_name `
    -DomainNetbiosName $domain_netbios_name `
    -SafeModeAdministratorPassword $SecureAdminPass `
    -InstallDNS `
    -Force `
    -NoRebootOnCompletion:$false
