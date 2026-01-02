Write-Host "Running Sysprep..."

Start-Process -FilePath "C:\Windows\System32\Sysprep\Sysprep.exe" `
  -ArgumentList "/generalize /oobe /shutdown /quiet /unattend:C:\Windows\System32\Sysprep\unattend.xml" `
  -Wait
