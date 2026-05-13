<#
.SYNOPSIS
    A.N.C.H.O.R. — Audits Native Cloud Hookups & OneDrive Readiness
    LiveConnect-Compatible OneDrive Known-Folder-Move Pre-Migration Validator for PowerShell 5.1+

.DESCRIPTION
    Audits OneDrive readiness on the local machine: client install, running
    state, signed-in accounts (Business / Personal), Known Folder Move
    redirection (Desktop / Documents / Pictures), content volume per folder,
    and recent OneDrive sync errors. Produces a dark-themed HTML report
    with a red / yellow / green readiness verdict.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.
    Reads HKCU\Software\Microsoft\OneDrive\Accounts for the running session's
    user — run interactively as that user to get accurate account data.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\anchor.ps1
    PS C:\> .\anchor.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : T.E.T.H.E.R. (main toolkit)
#>

param([string]$ReportPath = "C:\Temp")

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "ANCHOR_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  A.N.C.H.O.R. -- Audits Native Cloud Hookups & OneDrive Readiness" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As    : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time      : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Report    : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function Format-Bytes([long]$b) {
    if ($null -eq $b -or $b -le 0) { return '0 B' }
    $units = 'B','KB','MB','GB','TB'; $i = 0
    while ($b -ge 1024 -and $i -lt $units.Count - 1) { $b = $b / 1024; $i++ }
    return ('{0:N1} {1}' -f $b, $units[$i])
}

# ===========================
# COLLECTORS
# ===========================

function Get-OneDriveClient {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        'C:\Program Files\Microsoft OneDrive\OneDrive.exe',
        'C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe'
    )
    $exe = $null
    foreach ($p in $candidates) { if (Test-Path $p) { $exe = $p; break } }
    $version = $null
    if ($exe) { try { $version = (Get-Item $exe).VersionInfo.ProductVersion } catch { $version = 'unknown' } }
    $running = $false
    try { $running = [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue) } catch {}
    return [PSCustomObject]@{
        Installed = [bool]$exe; Path = $exe; Version = $version; Running = $running
    }
}

function Get-OneDriveAccounts {
    $root = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    if (-not (Test-Path $root)) { return @() }
    $accounts = foreach ($child in Get-ChildItem $root -ErrorAction SilentlyContinue) {
        try { $props = Get-ItemProperty -Path $child.PSPath -ErrorAction Stop } catch { continue }
        $type = if ($child.PSChildName -like 'Business*') { 'Business' }
                elseif ($child.PSChildName -eq 'Personal') { 'Personal' }
                else { 'Unknown' }
        [PSCustomObject]@{
            AccountKey  = $child.PSChildName
            AccountType = $type
            UserEmail   = $props.UserEmail
            UserFolder  = $props.UserFolder
            TenantId    = $props.ConfiguredTenantId
            DisplayName = $props.DisplayName
        }
    }
    return @($accounts)
}

$script:KfmFolders = @(
    @{ Label = 'Desktop';   ShellName = 'Desktop' }
    @{ Label = 'Documents'; ShellName = 'Personal' }
    @{ Label = 'Pictures';  ShellName = 'My Pictures' }
)

function Get-KfmStatus {
    $shellKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $results = foreach ($folder in $script:KfmFolders) {
        $path = $null
        try {
            $raw = (Get-ItemProperty -Path $shellKey -Name $folder.ShellName -ErrorAction Stop).($folder.ShellName)
            $path = [Environment]::ExpandEnvironmentVariables($raw)
        } catch {}
        $inOneDrive = $false
        if ($path) {
            $inOneDrive = ($path -match '(?i)\\OneDrive') -or
                          ($path -like "$env:OneDrive*") -or
                          ($path -like "$env:OneDriveCommercial*")
        }
        [PSCustomObject]@{ Label = $folder.Label; Path = if ($path) { $path } else { '(not set)' }; Redirected = $inOneDrive }
    }
    return @($results)
}

function Get-FolderVolume {
    param([array]$KfmStatus)
    $results = foreach ($f in $KfmStatus) {
        $count = 0; $bytes = 0L; $errMsg = $null
        if ($f.Path -and (Test-Path -LiteralPath $f.Path)) {
            try {
                $items = Get-ChildItem -LiteralPath $f.Path -Recurse -File -Force -ErrorAction SilentlyContinue
                $count = @($items).Count
                $sum = ($items | Measure-Object -Property Length -Sum).Sum
                if ($sum) { $bytes = [long]$sum }
            } catch { $errMsg = $_.Exception.Message }
        } else { $errMsg = 'Path does not exist' }
        [PSCustomObject]@{
            Label = $f.Label; Path = $f.Path
            FileCount = $count; Bytes = $bytes; Size = Format-Bytes $bytes; Error = $errMsg
        }
    }
    return @($results)
}

function Get-SyncErrors {
    $since = (Get-Date).AddDays(-7)
    $events = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = 'Application'
            ProviderName = @('OneDrive', 'Microsoft-Windows-User Profiles Service')
            Level        = 1, 2, 3
            StartTime    = $since
        } -ErrorAction SilentlyContinue
    } catch {
        try {
            $events = Get-WinEvent -LogName Application -MaxEvents 500 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.TimeCreated -ge $since -and
                    $_.LevelDisplayName -in @('Error','Warning','Critical') -and
                    ($_.ProviderName -like '*OneDrive*' -or $_.Message -match 'OneDrive')
                }
        } catch { $events = @() }
    }
    $rows = foreach ($e in $events) {
        [PSCustomObject]@{
            Time     = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
            Level    = "$($e.LevelDisplayName)"
            Provider = $e.ProviderName
            EventId  = $e.Id
            Message  = ($e.Message -split "`n" | Select-Object -First 1).Trim()
        }
    }
    return @($rows)
}

function Get-AnchorVerdict {
    param($Client, [array]$Accounts, [array]$Kfm, [array]$Volume, [array]$Errors)
    $issues = @(); $warns = @()
    if (-not $Client.Installed)     { $issues += 'OneDrive client is not installed.' }
    elseif (-not $Client.Running)   { $warns  += 'OneDrive client is installed but not currently running.' }
    $businessAccounts = @($Accounts | Where-Object { $_.AccountType -eq 'Business' -and $_.UserEmail })
    if ($businessAccounts.Count -eq 0) { $issues += 'No Business/Work OneDrive account is signed in.' }
    foreach ($r in ($Kfm | Where-Object { -not $_.Redirected })) {
        $issues += "Known Folder '$($r.Label)' is not redirected to OneDrive."
    }
    foreach ($v in $Volume) {
        if ($v.Bytes -gt 25GB) { $warns += "Folder '$($v.Label)' is $($v.Size) -- large uploads may take time." }
    }
    $errCount = @($Errors).Count
    if ($errCount -gt 0) { $warns += "$errCount OneDrive Application-log errors/warnings in the last 7 days." }
    $verdict = if ($issues.Count -gt 0) { 'NOT READY' } elseif ($warns.Count -gt 0) { 'READY WITH WARNINGS' } else { 'READY' }
    $class   = if ($issues.Count -gt 0) { 'crit' }      elseif ($warns.Count -gt 0) { 'warn' }                else { 'ok' }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] OneDrive client..." -ForegroundColor Magenta
$client = Get-OneDriveClient
if ($client.Installed) {
    Write-Host ("  [OK] Installed: {0} (v{1})" -f $client.Path, $client.Version) -ForegroundColor Green
    Write-Host ("  Process running: {0}" -f $client.Running) -ForegroundColor $(if ($client.Running) { 'Green' } else { 'Yellow' })
} else {
    Write-Host "  [!!] OneDrive client is NOT installed." -ForegroundColor Red
}
Write-Host ""

Write-Host "[*] Signed-in accounts..." -ForegroundColor Magenta
$accounts = Get-OneDriveAccounts
if ($accounts.Count -eq 0) {
    Write-Host "  [!!] No OneDrive accounts signed in." -ForegroundColor Red
} else {
    foreach ($a in $accounts) {
        $color = if ($a.AccountType -eq 'Business') { 'Green' } else { 'Yellow' }
        Write-Host ("  [{0,-8}] {1}" -f $a.AccountType, $a.UserEmail) -ForegroundColor $color
        Write-Host ("    Sync root : {0}" -f $a.UserFolder) -ForegroundColor Gray
    }
}
Write-Host ""

Write-Host "[*] Known Folder redirection..." -ForegroundColor Magenta
$kfm = Get-KfmStatus
foreach ($k in $kfm) {
    if ($k.Redirected) {
        Write-Host ("  [OK] {0,-10} -> redirected to OneDrive" -f $k.Label) -ForegroundColor Green
    } else {
        Write-Host ("  [!!] {0,-10} -> local only ({1})" -f $k.Label, $k.Path) -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "[*] Content volume..." -ForegroundColor Magenta
$volume = Get-FolderVolume -KfmStatus $kfm
foreach ($v in $volume) {
    $color = if ($v.Bytes -ge 25GB) { 'Red' } elseif ($v.Bytes -ge 5GB) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-12} {1,8} files  {2}" -f $v.Label, $v.FileCount, $v.Size) -ForegroundColor $color
}
Write-Host ""

Write-Host "[*] Sync errors (last 7 days)..." -ForegroundColor Magenta
$errors = Get-SyncErrors
if ($errors.Count -eq 0) {
    Write-Host "  [OK] No OneDrive errors in the last 7 days." -ForegroundColor Green
} else {
    Write-Host "  [!!] $($errors.Count) event(s) in the last 7 days." -ForegroundColor Yellow
    foreach ($e in $errors | Select-Object -First 10) {
        $color = if ($e.Level -in 'Error','Critical') { 'Red' } else { 'Yellow' }
        Write-Host ("    [{0}] {1} (id={2}): {3}" -f $e.Time, $e.Level, $e.EventId, $e.Message) -ForegroundColor $color
    }
}
Write-Host ""

$verdict = Get-AnchorVerdict -Client $client -Accounts $accounts -Kfm $kfm -Volume $volume -Errors $errors

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ONEDRIVE READINESS VERDICT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$vColor = switch ($verdict.Class) { 'ok' { 'Green' } 'warn' { 'Yellow' } default { 'Red' } }
Write-Host "  $($verdict.Verdict)" -ForegroundColor $vColor
foreach ($i in $verdict.Issues) { Write-Host "    [!!] $i" -ForegroundColor Red }
foreach ($w in $verdict.Warns)  { Write-Host "    [~ ] $w" -ForegroundColor Yellow }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    Write-Host "    [+ ] All checks passed." -ForegroundColor Green
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$clientRow = if ($client.Installed) {
    $runBadge = if ($client.Running) { "<span class='badge badge-ok'>Running</span>" } else { "<span class='badge badge-warn'>Not running</span>" }
    "<tr><td><span class='badge badge-ok'>Installed</span></td><td>$(HtmlEncode $client.Version)</td><td>$runBadge</td><td><code>$(HtmlEncode $client.Path)</code></td></tr>"
} else {
    "<tr><td colspan='4' style='text-align:center;'><span class='badge badge-crit'>OneDrive client is NOT installed</span></td></tr>"
}

$acctRows = ""
if ($accounts.Count -eq 0) {
    $acctRows = "<tr><td colspan='4' style='text-align:center;'><span class='badge badge-crit'>No OneDrive accounts signed in</span></td></tr>"
} else {
    foreach ($a in $accounts) {
        $tb = switch ($a.AccountType) {
            'Business' { "<span class='badge badge-ok'>Business</span>" }
            'Personal' { "<span class='badge badge-warn'>Personal</span>" }
            default    { "<span class='badge badge-neutral'>Unknown</span>" }
        }
        $acctRows += "<tr><td>$tb</td><td>$(HtmlEncode $a.UserEmail)</td><td><code>$(HtmlEncode $a.UserFolder)</code></td><td><code>$(HtmlEncode $a.TenantId)</code></td></tr>"
    }
}

$kfmRows = ""
foreach ($k in $kfm) {
    $badge = if ($k.Redirected) { "<span class='badge badge-ok'>Redirected</span>" } else { "<span class='badge badge-crit'>Local only</span>" }
    $kfmRows += "<tr><td>$(HtmlEncode $k.Label)</td><td>$badge</td><td><code>$(HtmlEncode $k.Path)</code></td></tr>"
}

$volRows = ""
foreach ($v in $volume) {
    $cls = if ($v.Bytes -ge 25GB) { 'badge-crit' } elseif ($v.Bytes -ge 5GB) { 'badge-warn' } else { 'badge-ok' }
    $errCell = if ($v.Error) { "<span class='badge badge-warn'>$(HtmlEncode $v.Error)</span>" } else { '' }
    $volRows += "<tr><td>$(HtmlEncode $v.Label)</td><td>$($v.FileCount)</td><td><span class='badge $cls'>$(HtmlEncode $v.Size)</span></td><td>$errCell</td></tr>"
}

$errRows = ""
if ($errors.Count -eq 0) {
    $errRows = "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No OneDrive errors in the last 7 days.</td></tr>"
} else {
    foreach ($e in $errors | Select-Object -First 50) {
        $lvl = if ($e.Level -in 'Error','Critical') { 'badge-crit' } else { 'badge-warn' }
        $errRows += "<tr><td>$(HtmlEncode $e.Time)</td><td><span class='badge $lvl'>$(HtmlEncode $e.Level)</span></td><td>$($e.EventId)</td><td>$(HtmlEncode $e.Message)</td></tr>"
    }
}

$verdictBlock = ""
foreach ($i in $verdict.Issues) { $verdictBlock += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $verdictBlock += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $verdictBlock = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>All pre-migration checks passed.</li>"
}

$totalBytesSum = ($volume | Measure-Object -Property Bytes -Sum).Sum
if (-not $totalBytesSum) { $totalBytesSum = 0 }
$totalContent = Format-Bytes ([long]$totalBytesSum)
$redirCount   = @($kfm | Where-Object { $_.Redirected }).Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>A.N.C.H.O.R. OneDrive -- $env:COMPUTERNAME</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', Consolas, monospace; font-size: 14px; padding: 24px; }
  h1 { color: #00d4ff; font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 24px; }
  .summary { display: flex; gap: 14px; flex-wrap: wrap; margin-bottom: 28px; }
  .card { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 16px 24px; min-width: 130px; text-align: center; }
  .card .val { font-size: 22px; font-weight: bold; color: #00d4ff; }
  .card .lbl { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-top: 4px; }
  .card.warn .val { color: #f39c12; }
  .card.crit .val { color: #e74c3c; }
  .card.ok   .val { color: #2ecc71; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th { background: #0f3460; color: #00d4ff; padding: 10px 12px; text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
  td { padding: 9px 12px; border-bottom: 1px solid #1e2d4d; vertical-align: top; word-break: break-word; }
  tr:hover td { background: #1e2d4d; }
  code { background: #0f1928; padding: 1px 6px; border-radius: 3px; font-size: 12px; color: #00d4ff; word-break: break-all; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; }
  .badge-ok      { background: #1a4a2e; color: #2ecc71; }
  .badge-warn    { background: #4a3a10; color: #f39c12; }
  .badge-crit    { background: #4a1a1a; color: #e74c3c; }
  .badge-neutral { background: #2a2a3e; color: #aaa; }
  .section-title { color: #00d4ff; font-size: 15px; margin: 28px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  ul { list-style: none; padding-left: 0; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>A.N.C.H.O.R. -- OneDrive Pre-Migration Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Run As: $env:USERDOMAIN\$env:USERNAME &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Migration Readiness</div></div>
  <div class="card"><div class="val">$($accounts.Count)</div><div class="lbl">OneDrive Accounts</div></div>
  <div class="card"><div class="val">$redirCount / $($kfm.Count)</div><div class="lbl">Folders Redirected</div></div>
  <div class="card"><div class="val">$totalContent</div><div class="lbl">Total Content</div></div>
  <div class="card $(if ($errors.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($errors.Count)</div><div class="lbl">Sync Errors (7d)</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$verdictBlock</ul>

<div class="section-title">OneDrive Client</div>
<table>
  <thead><tr><th>Installed</th><th>Version</th><th>Process</th><th>Path</th></tr></thead>
  <tbody>$clientRow</tbody>
</table>

<div class="section-title">Signed-In Accounts ($($accounts.Count))</div>
<table>
  <thead><tr><th>Type</th><th>Email</th><th>Sync Root</th><th>Tenant ID</th></tr></thead>
  <tbody>$acctRows</tbody>
</table>

<div class="section-title">Known Folder Redirection</div>
<table>
  <thead><tr><th>Folder</th><th>Status</th><th>Resolved Path</th></tr></thead>
  <tbody>$kfmRows</tbody>
</table>

<div class="section-title">Content Volume</div>
<table>
  <thead><tr><th>Folder</th><th>File Count</th><th>Size</th><th>Error</th></tr></thead>
  <tbody>$volRows</tbody>
</table>

<div class="section-title">Sync Errors (last 7 days)</div>
<table>
  <thead><tr><th>Time</th><th>Level</th><th>Event ID</th><th>Message</th></tr></thead>
  <tbody>$errRows</tbody>
</table>

<div class="footer">
  Generated by A.N.C.H.O.R. -- Technician Toolkit LiveConnect Suite. Reads HKCU for the running user's OneDrive accounts.
</div>
</body>
</html>
"@

try {
    [System.IO.File]::WriteAllText($reportFullPath, $html, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Report saved: $reportFullPath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Could not save report: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] A.N.C.H.O.R. complete." -ForegroundColor Cyan
Write-Host ""
