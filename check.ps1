# Diagnoses a claude-hebrew-rtl install. Changes nothing. Each line: [OK] or [FIX] with what to do.
$ErrorActionPreference = 'Continue'
$fails = 0
function Report($ok, $what, $fix) {
    if ($ok) { Write-Host "[OK]  $what" -ForegroundColor Green }
    else { Write-Host "[FIX] $what -> $fix" -ForegroundColor Red; $script:fails++ }
}

# Claude Desktop ships both as a Store/MSIX package and as a classic installer: accept either.
$pkg = Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue
$desktop = [bool]$pkg -or (Test-Path "$env:LOCALAPPDATA\AnthropicClaude") -or (Test-Path "$env:APPDATA\Claude")
Report $desktop 'Claude Desktop installed' 'install it from https://claude.ai/download'

$claude = (Get-Command claude.cmd -ErrorAction SilentlyContinue).Source
if (-not $claude) {
    $claude = Get-ChildItem "$env:APPDATA\Claude\claude-code" -Recurse -Filter claude.exe -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
Report ([bool]$claude) 'Claude Code engine found' 'open the Code tab in Claude Desktop once, then run install again'

if ($claude) {
    $list = (& $claude plugin list 2>&1 | Out-String)
    Report ($list -match 'smart-rtl-he@claude-hebrew-rtl') 'Plugin smart-rtl-he installed' 'run install.ps1 again'
    Report (-not ($list -match 'smart-rtl@smart-rtl|smart-rtl-he@smart-rtl-he')) 'No older RTL plugin installed' "remove it: claude plugin uninstall <name> (from: $claude)"
}

$ahk = @("$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
Report ([bool]$ahk) 'AutoHotkey v2 installed' 'winget install AutoHotkey.AutoHotkey --version 2.0.26 --scope user, or https://www.autohotkey.com'

$script = Join-Path $env:LOCALAPPDATA 'ClaudeHebrewRTL\input\claude-rtl.ahk'
Report (Test-Path $script) 'Input-box script in place' 'run install.ps1 again'
$running = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -like '*claude-rtl.ahk*' })
Report ($running.Count -eq 1) "Input-box helper running (instances: $($running.Count))" 'run install.ps1 again; if it keeps dying, allow AutoHotkey in the antivirus; more than 1 = remove old Startup shortcuts and sign out/in'
Report (Test-Path (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Hebrew RTL.lnk')) 'Starts with Windows' 'run install.ps1 again'

Report ([bool]((Get-WinUserLanguageList).LanguageTag | Where-Object { $_ -like 'he*' })) 'Hebrew keyboard in Windows' 'Settings > Time & language > Language & region > Add a language > Hebrew'

$patch = Get-ScheduledTask -TaskName ClaudeRtlPatchWatcher -ErrorAction SilentlyContinue
Report (-not $patch) 'Old binary RTL patch (shraga100) not active' 'it re-patches Claude and can make it crash: remove it with its own menu (options 5 then 2) as administrator'

Write-Host ''
if ($fails) { Write-Host "$fails thing(s) to fix." -ForegroundColor Red } else { Write-Host 'ALL OK. Open a NEW chat in the Claude Code tab.' -ForegroundColor Green }
