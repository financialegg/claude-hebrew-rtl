# Installs Hebrew RTL for Claude Desktop: the Claude plugin (replies and prompts) and the
# AutoHotkey input-box helper. No admin rights, no change to Claude's own files.
$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'ClaudeHebrewRTL'

Write-Host '[1/4] Copying files to' $dest
New-Item -ItemType Directory -Force -Path $dest | Out-Null
if ($PSScriptRoot -ne $dest) { Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $dest -Recurse -Force }

# The npm 'claude' if installed, else the one Claude Desktop ships with.
$claude = (Get-Command claude.cmd -ErrorAction SilentlyContinue).Source
if (-not $claude) {
    $claude = Get-ChildItem "$env:APPDATA\Claude\claude-code" -Recurse -Filter claude.exe -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $claude) { throw 'Claude Desktop was not found. Install it from https://claude.ai/download, open the Code tab once, then run this again.' }

Write-Host '[2/4] Installing the Claude plugin...'
# ponytail: remove-then-add makes a re-run an update; errors from the remove are expected on a first install.
$ErrorActionPreference = 'Continue'   # PS 5.1 turns a native tool's stderr into errors
& $claude plugin marketplace remove claude-hebrew-rtl 2>&1 | Out-Null
& $claude plugin marketplace add $dest
& $claude plugin install smart-rtl-he@claude-hebrew-rtl
if ($LASTEXITCODE -ne 0) { throw 'The Claude plugin did not install. See the message above.' }
$ErrorActionPreference = 'Stop'

Write-Host '[3/4] Making sure AutoHotkey v2 is installed...'
$ahk = @("$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available on this computer. Install AutoHotkey v2 by hand from https://www.autohotkey.com (the default options are fine), then run this again.'
    }
    winget install AutoHotkey.AutoHotkey --version 2.0.26 --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity
    $ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    if (-not (Test-Path $ahk)) { throw 'AutoHotkey did not install. Install AutoHotkey v2 from https://www.autohotkey.com and run this again.' }
}

Write-Host '[4/4] Starting the input-box helper and adding it to Windows startup...'
$script = Join-Path $dest 'input\claude-rtl.ahk'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Hebrew RTL.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = $ahk
$s.Arguments = '"' + $script + '"'
$s.WorkingDirectory = Split-Path $script
$s.Description = 'Hebrew right-to-left in the Claude Desktop input box'
$s.Save()
Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '"')   # the script is #SingleInstance Force

Write-Host ''
Write-Host 'Self-check:'
Start-Sleep -Seconds 2
$problems = @()
$ErrorActionPreference = 'Continue'
if (-not (& $claude plugin list 2>&1 | Select-String 'smart-rtl-he@claude-hebrew-rtl')) { $problems += 'The Claude plugin is not listed.' }
$ErrorActionPreference = 'Stop'
if (-not (Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' })) { $problems += 'The input-box helper is not running (antivirus?).' }
if (-not ((Get-WinUserLanguageList).LanguageTag | Where-Object { $_ -like 'he*' })) { $problems += 'No Hebrew keyboard in Windows: Settings > Time & language > Language, add Hebrew.' }
if ($problems) {
    Write-Host 'PROBLEMS FOUND - send a screenshot of this window:' -ForegroundColor Red
    $problems | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
} else {
    Write-Host 'ALL OK' -ForegroundColor Green
}

Write-Host ''
Write-Host 'Done. Open a NEW chat in the Claude Code tab (chats that were already open keep the old state), switch the keyboard to Hebrew and type.'
Write-Host 'If the input box ever scrambles: Ctrl+Alt+J. Pause/resume the helper: Ctrl+Alt+Shift+R.'
