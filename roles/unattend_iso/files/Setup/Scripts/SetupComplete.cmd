@echo off
echo ==== SetupComplete START ==== > C:\sysprep.log

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File C:\Windows\Setup\Scripts\sysprep.ps1 ^
  >> C:\sysprep.log 2>&1

shutdown /s /t 0
exit /b 0
