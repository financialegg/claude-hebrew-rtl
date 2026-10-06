# One-line install from GitHub, in PowerShell:
#   irm https://raw.githubusercontent.com/financialegg/claude-hebrew-rtl/main/get.ps1 | iex
# Downloads the repository as a ZIP, unpacks it in TEMP and runs its install.ps1.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$zip = Join-Path $env:TEMP 'claude-hebrew-rtl.zip'
$dir = Join-Path $env:TEMP 'claude-hebrew-rtl-main'   # the folder name GitHub gives the main-branch ZIP
Write-Host 'Downloading claude-hebrew-rtl from GitHub...'
Invoke-WebRequest 'https://github.com/financialegg/claude-hebrew-rtl/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
Expand-Archive $zip -DestinationPath $env:TEMP -Force
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'install.ps1')
