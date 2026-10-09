# Removes everything install.ps1 added. AutoHotkey itself stays (other tools may use it).
$dest = Join-Path $env:USERPROFILE '.claude-hebrew-rtl'
$old = Join-Path $env:LOCALAPPDATA 'ClaudeHebrewRTL'   # earlier versions

$claude = (Get-Command claude.cmd -ErrorAction SilentlyContinue).Source
if (-not $claude) {
    $claude = Get-ChildItem "$env:APPDATA\Claude\claude-code" -Recurse -Filter claude.exe -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if ($claude) {
    Write-Host 'Removing the Claude plugin...'
    & $claude plugin uninstall smart-rtl-he@claude-hebrew-rtl
    & $claude plugin marketplace remove claude-hebrew-rtl
}

Write-Host 'Stopping the input-box helper...'
Unregister-ScheduledTask -TaskName ClaudeHebrewRTL -Confirm:$false -ErrorAction SilentlyContinue   # first: it would start the helper again
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
    Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'ClaudeHebrewRTL' -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Hebrew RTL.lnk') -ErrorAction SilentlyContinue   # older installs
if (Test-Path $dest) { Remove-Item $dest -Recurse -ErrorAction SilentlyContinue }
if ((Test-Path (Join-Path $old 'input\claude-rtl.ahk')) -and -not (Test-Path (Join-Path $old '.git'))) { Remove-Item $old -Recurse -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host 'Done. To remove AutoHotkey too: winget uninstall AutoHotkey.AutoHotkey'
