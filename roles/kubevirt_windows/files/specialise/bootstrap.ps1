$marker = "C:\kubevirt_init.done"

$SecureAdminPass = ConvertTo-SecureString "Admin123!" -AsPlainText -Force
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

Write-Host "Configuring as Domain Controller..."

# Non-interactive feature install
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -Confirm:$false -Restart:$false

# Reliable DC detection
$ntds = Get-Service NTDS -ErrorAction SilentlyContinue
if ($null -eq $ntds -or $ntds.Status -ne 'Running') {
    Write-Host "Starting AD forest creation (will reboot)"
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
