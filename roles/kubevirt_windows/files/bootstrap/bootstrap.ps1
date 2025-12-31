# At the start of bootstrap.ps1, check for state file
$stateFile = "C:\Windows\Setup\Scripts\bootstrap-state.txt"

$computer_name = "DC-Root"
$ip_address = "192.168.10.10"
$dns_address = "192.168.10.10"
$admin_password = "Admin123!"
$SecureAdminPass = ConvertTo-SecureString $admin_password -AsPlainText -Force
$domain_name = "example.local"
$domain_netbios_name = "EXAMPLE"

# Function to enable auto-logon
function Enable-AutoLogon {
    param(
        [string]$Username = "Administrator",
        [string]$Password,
        [string]$Domain = ""
    )
    
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value $Username
    Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value $Password
    
    if ($Domain) {
        Set-ItemProperty -Path $regPath -Name "DefaultDomainName" -Value $Domain
    }
    
    # Remove the LogonCount limit
    Remove-ItemProperty -Path $regPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
}

# Function to disable auto-logon
function Disable-AutoLogon {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "0"
    Remove-ItemProperty -Path $regPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $regPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
}

if (Test-Path $stateFile) {
    $state = Get-Content $stateFile
} else {
    $state = "initial-setup"
}

switch ($state) {
    "initial-setup" {
        Write-Host "Setting computer name..."

        $interface = (Get-NetAdapter | Where-Object Status -eq "Up")[0].Name
        New-NetIPAddress -InterfaceAlias $interface -IPAddress $ip_address -PrefixLength 24
        Set-DnsClientServerAddress -InterfaceAlias $interface -ServerAddresses $dns_address

        Set-LocalUser -Name Administrator -Password $SecureAdminPass
        Rename-Computer -NewName $computer_name

        # Set next state
        "install-ad" | Out-File -FilePath $stateFile
        
        # Enable auto-logon for next boot
        Enable-AutoLogon -Username "Administrator" -Password $admin_password
        
        # Register to run again after reboot
        $runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\bootstrap.ps1"
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootstrapContinue" -Value $runOnceCommand
        
        Restart-Computer -Force
    }

    "install-ad" {
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

        # Set next state
        "ad-setup" | Out-File -FilePath $stateFile

        # Keep auto-logon enabled for next boot
        Enable-AutoLogon -Username "Administrator" -Password $admin_password

        # Register to run again after reboot
        $runOnceCommand = "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\bootstrap.ps1"
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootstrapContinue" -Value $runOnceCommand

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
    }
    
    "ad-setup" {
        Write-Host "Running post-reboot setup..."
        Start-Sleep -Seconds 30
        
        Import-Module ActiveDirectory

        # Rename default site to RootSite
        Get-ADReplicationSite "Default-First-Site-Name" | Rename-ADObject -NewName "RootSite"
        Write-Host "Renamed Default-First-Site-Name to RootSite"

        # Create additional sites
        $sites = @("Site1","Site2")
        foreach ($site in $sites) {
            if (-not (Get-ADReplicationSite -Filter "Name -eq '$site'")) {
                New-ADReplicationSite -Name $site
                Write-Host "Created site: $site"
            }
        }

        # Fixed subnets with unique addresses
        $subnets = @(
            @{Subnet="192.168.10.0/24"; Site="RootSite"},
            @{Subnet="192.168.11.0/24"; Site="Site1"},
            @{Subnet="192.168.12.0/24"; Site="Site2"}
        )

        foreach ($s in $subnets) {
            if (-not (Get-ADReplicationSubnet -Filter "Name -eq '$($s.Subnet)'")) {
                New-ADReplicationSubnet -Name $s.Subnet -Site $s.Site
                Write-Host "Created subnet $($s.Subnet) assigned to site $($s.Site)"
            }
        }
        
        # DISABLE auto-logon now that setup is complete
        Write-Host "Disabling auto-logon..."
        Disable-AutoLogon
        
        # Clean up
        Remove-Item $stateFile -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "BootstrapContinue" -ErrorAction SilentlyContinue
        
        Write-Host "Bootstrap complete! Manual login required from now on."

        Restart-Computer -Force
    }
}