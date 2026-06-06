$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "Stopping InkConnect local processes..."

Get-Process | Where-Object { $_.ProcessName -eq "inkconnect-api" } | Stop-Process -Force
Get-Process | Where-Object { $_.ProcessName -like "dart*" } | Stop-Process -Force
Get-Process | Where-Object { $_.ProcessName -like "flutter*" } | Stop-Process -Force

Write-Host "Done."
