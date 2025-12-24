@echo off
echo ==== SetupComplete START ==== > C:\kubevirt_init.log

powershell.exe -NoProfile -ExecutionPolicy Bypass ^
  -File C:\Windows\Setup\Scripts\kubevirt_init.ps1 ^
  >> C:\kubevirt_init.log 2>&1

shutdown /s /t 0
exit /b 0