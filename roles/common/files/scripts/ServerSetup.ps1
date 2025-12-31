# Set up all VMs on the same internal switch in Hyper-V

# Use unattended install mounted as separate ISO to Windows Server 2022

# Root DC

## Rename server
Rename-Computer -NewName "DC-Root" -Restart

## Set static IPs
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.10.10 -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.10.10

## Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

## Promote to Root Domain Controller
$SecurePassword = ConvertTo-SecureString "Admin123!" -AsPlainText -Force

Install-ADDSForest `
    -DomainName "corp.local" `
    -DomainNetbiosName "CORP" `
    -InstallDNS `
    -CreateDNSDelegation:$false `
    -SafeModeAdministratorPassword $SecurePassword `
    -Force

## Set replication to 5 minutes for lab
Set-ADReplicationSiteLink -Identity "DEFAULTIPSITELINK" -ReplicationFrequencyInMinutes 5

New-ADReplicationSiteLink -Name "FullMesh" -SitesIncluded "RootSite","Site1","Site2" -Cost 100 -ReplicationFrequencyInMinutes 5

# Child DC1

## Rename server
Rename-Computer -NewName "DC-Site1" -Restart

## Set static IPs
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.10.11 -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.10.10

## Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

## Promote to Domain Controller
$SecurePassword = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
$Cred = Get-Credential  # enter domain admin credentials for corp.local

Install-ADDSDomainController `
    -Credential $Cred `
    -DomainName "corp.local" `
    -InstallDNS `
    -SafeModeAdministratorPassword $SecurePassword `
    -Force

## Set replication to 5 minutes for lab
Set-ADReplicationSiteLink -Identity "DEFAULTIPSITELINK" -ReplicationFrequencyInMinutes 5


# Child DC2

## Rename server
Rename-Computer -NewName "DC-Site2" -Restart

## Set static IPs
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.10.12 -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.10.10

## Install AD DS role
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

## Promote to Domain Controller
$SecurePassword = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
$Cred = Get-Credential  # enter domain admin credentials for corp.local

Install-ADDSDomainController `
    -Credential $Cred `
    -DomainName "corp.local" `
    -InstallDNS `
    -SafeModeAdministratorPassword $SecurePassword `
    -Force

## Set replication to 5 minutes for lab
Set-ADReplicationSiteLink -Identity "DEFAULTIPSITELINK" -ReplicationFrequencyInMinutes 5

# Set up AD Sites

# -------------------------------
# AD Sites & Subnets Setup Script
# Run on Root DC
# -------------------------------

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
 