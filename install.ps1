# Installs Hebrew RTL for Claude Desktop: the Claude plugin (replies and prompts) and the
# AutoHotkey input-box helper. No admin rights, no change to Claude's own files.
$ErrorActionPreference = 'Stop'
# NOT under AppData: Claude Desktop is an MSIX app, and a new folder created directly under %LOCALAPPDATA% or %APPDATA%
# from inside it lands in the app's private store, which Windows itself (sign-in, Task Scheduler, a normal terminal)
# cannot see. That showed up as "Script file not found" at every sign-in. The user profile folder is visible to everyone.
$dest = Join-Path $env:USERPROFILE '.claude-hebrew-rtl'
Write-Host '[1/4] Copying files to' $dest
New-Item -ItemType Directory -Force -Path $dest | Out-Null
if ($PSScriptRoot -ne $dest) { Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $dest -Recurse -Force }

# Earlier versions installed under %LOCALAPPDATA%\ClaudeHebrewRTL. Remove that copy (never a git work tree of someone's own).
$old = Join-Path $env:LOCALAPPDATA 'ClaudeHebrewRTL'
if ((Test-Path (Join-Path $old 'input\claude-rtl.ahk')) -and -not (Test-Path (Join-Path $old '.git'))) { Remove-Item $old -Recurse -ErrorAction SilentlyContinue }

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

Write-Host '[4/4] Starting the input-box helper and keeping it running...'
$script = Join-Path $dest 'input\claude-rtl.ahk'
$keep = Join-Path $dest 'input\keepalive.ahk'
$problems = @()
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$cmd = '"' + $ahk + '" "' + $script + '"'
$tn = 'ClaudeHebrewRTL'
# Startup is a scheduled task, not a .lnk shortcut: a shortcut keeps its path in the ANSI code page, so a Hebrew,
# Russian or Arabic user name turns into '?' and Windows shows "Script file not found" at every sign-in.
# The task runs keepalive.ahk at sign-in and every minute; it starts the helper only if it is not running. That also
# brings the helper back after a Claude update, which closes anything that was started from Claude's own shell.
$taskOk = $false
try {
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $act = New-ScheduledTaskAction -Execute $ahk -Argument ('"' + $keep + '"') -WorkingDirectory (Split-Path $keep)
    $trg = @((New-ScheduledTaskTrigger -AtLogOn -User $me),
             (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)))
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -Hidden
    $prin = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $tn -Description 'Keeps the Hebrew right-to-left input helper for Claude Desktop running' -Action $act -Trigger $trg -Settings $set -Principal $prin -Force | Out-Null
    $taskOk = $true
} catch { }
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Hebrew RTL.lnk') -ErrorAction SilentlyContinue   # older installs used a shortcut
# a helper left from an older install would keep running the old script
Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
if ($taskOk) {
    Remove-ItemProperty -Path $run -Name 'ClaudeHebrewRTL' -ErrorAction SilentlyContinue   # the task replaces the older Run entry
    Start-ScheduledTask -TaskName $tn
} else {
    # no Task Scheduler (policy?): a registry Run value is the Unicode-safe startup entry; start the helper now
    try { Set-ItemProperty -Path $run -Name 'ClaudeHebrewRTL' -Value $cmd -Type String }
    catch { $problems += 'Could not add the helper to Windows startup (blocked by policy or antivirus?). It works until you sign out.' }
    Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '"')   # the script is #SingleInstance Force
}

Write-Host ''
Write-Host 'Self-check:'
# the task starts the helper within a couple of seconds; wait up to 15 s for it
for ($n = 0; $n -lt 30 -and -not (Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' }); $n++) { Start-Sleep -Milliseconds 500 }if ($taskOk) { if (-not (Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue)) { $problems += 'The startup task was not saved.' } }
elseif (-not $problems -and (Get-ItemProperty -Path $run).ClaudeHebrewRTL -cne $cmd) { $problems += 'The Windows startup entry was not saved correctly.' }
$ErrorActionPreference = 'Continue'
if (-not (& $claude plugin list 2>&1 | Select-String 'smart-rtl-he@claude-hebrew-rtl')) { $problems += 'The Claude plugin is not listed.' }
$ErrorActionPreference = 'Stop'
if (-not (Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' })) { $problems += 'The input-box helper is not running (antivirus?).' }
# can Windows itself, outside Claude, see the script? (a process started through WMI is not part of Claude's app)
$flag = Join-Path $env:PUBLIC 'claude-hebrew-rtl-check.txt'
Remove-Item $flag -ErrorAction SilentlyContinue
$null = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = ('cmd.exe /c if exist "' + $script + '" echo ok> "' + $flag + '"') }
for ($n = 0; $n -lt 20 -and -not (Test-Path $flag); $n++) { Start-Sleep -Milliseconds 250 }
$seen = Test-Path $flag
Remove-Item $flag -ErrorAction SilentlyContinue
if (-not $seen) { $problems += 'Windows cannot see the helper script outside Claude, so it would not start at sign-in. Run Uninstall.cmd, then install again.' }
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
