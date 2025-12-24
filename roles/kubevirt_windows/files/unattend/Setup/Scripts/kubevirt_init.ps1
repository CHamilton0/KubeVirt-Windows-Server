$marker = "C:\kubevirt_init.done"

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

# ==== Detect role from mounted ConfigMap ====
$roleFile = Join-Path $PSScriptRoot "role.txt"

if (-not (Test-Path $roleFile)) {
    Write-Host "No role file found, skipping AD configuration"
}
else {
    $roleData = Get-Content $roleFile
    switch ($roleData.Trim()) {

        "dc" {
            Write-Host "Configuring as Domain Controller..."

            # Non-interactive feature install
            Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Confirm:$false -Restart:$false

            # Reliable DC detection
            $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
            if ($null -eq $ntds -or $ntds.Status -ne 'Running') {
                Write-Host "Starting AD forest creation (will reboot)"
                $SecureAdminPass = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
                Install-ADDSForest `
                    -DomainName "example.local" `
                    -DomainNetbiosName "EXAMPLE" `
                    -SafeModeAdministratorPassword $SecureAdminPass `
                    -InstallDNS `
                    -Force `
                    -NoRebootOnCompletion:$false

                # AD WILL REBOOT automatically
                return
            }

            # CHANGED: second boot path (promotion finished)
            if ($ntds.Status -eq 'Running') {
                Write-Host "AD promotion complete"

                "BOOTSTRAP OK" | Out-File C:\bootstrap.txt
                New-Item -ItemType File $marker -Force

                Stop-Transcript
                Restart-Computer -Force
            }
        }

        "member" {
            Write-Host "Joining existing domain..."

            if (-not (Get-WmiObject Win32_ComputerSystem).PartOfDomain) {
                $domain = "example.local"
                $user = "Administrator"
                $pass = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
                $cred = New-Object System.Management.Automation.PSCredential($user, $pass)

                Add-Computer -DomainName $domain -Credential $cred -Force -Restart
                return
            }

            # After reboot
            "BOOTSTRAP OK" | Out-File C:\bootstrap.txt
            New-Item -ItemType File $marker -Force

            Stop-Transcript
            Restart-Computer -Force
        }

        default {
            Write-Host "Unknown role: $roleData"
        }
    }
}
