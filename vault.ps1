<#
.SYNOPSIS
    V.A.U.L.T. — Visits Aged Unindexed Long-forgotten Troves
    LiveConnect-Compatible Outlook PST / OST Discovery Tool for PowerShell 5.1+

.DESCRIPTION
    Scans the machine for Outlook data files (.pst and optionally .ost) on
    local fixed drives, cross-references them against configured Outlook
    profiles, flags orphaned and stale archives, and highlights files that
    exceed Exchange Online import limits (50 GB hard cap, 10 GB+ slow lane).
    Produces a dark-themed HTML report with a migration readiness verdict.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.
    Reads HKCU Outlook profile data for the running session's user.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\vault.ps1
    PS C:\> .\vault.ps1 -ReportPath "C:\Temp"
    PS C:\> .\vault.ps1 -ScanDrives "C:,D:" -IncludeOst

.PARAMETERS
    -ReportPath    Folder where the HTML report is saved (default: C:\Temp)
    -ScanDrives    Comma-separated drive letters to scan (default: all fixed drives)
    -IncludeOst    Also enumerate .ost files (default: PST only)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : E.X.H.U.M.E. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [string]$ScanDrives = "",
    [switch]$IncludeOst
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "VAULT_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

$DrivesArr = @()
if ($ScanDrives) {
    $DrivesArr = $ScanDrives.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

Write-Host ""
Write-Host "  V.A.U.L.T. -- Visits Aged Unindexed Long-forgotten Troves" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine     : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As      : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time        : $ExecutionTime" -ForegroundColor Gray
Write-Host "  ScanDrives  : $(if ($DrivesArr.Count -gt 0) { $DrivesArr -join ', ' } else { '(all fixed)' })" -ForegroundColor Gray
Write-Host "  IncludeOst  : $([bool]$IncludeOst)" -ForegroundColor Gray
Write-Host "  Report      : $reportFullPath" -ForegroundColor Gray
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

function Get-OutlookProfiles {
    $roots = @(
        'HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles',
        'HKCU:\Software\Microsoft\Office\15.0\Outlook\Profiles',
        'HKCU:\Software\Microsoft\Office\14.0\Outlook\Profiles'
    )
    $defaultProfile = $null
    try { $defaultProfile = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Office\16.0\Outlook' -Name 'DefaultProfile' -ErrorAction SilentlyContinue).DefaultProfile } catch {}

    $profiles = foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $version = if     ($root -match '16\.0') { 'Outlook 2016+' }
                   elseif ($root -match '15\.0') { 'Outlook 2013' }
                   elseif ($root -match '14\.0') { 'Outlook 2010' }
                   else { 'Unknown' }
        foreach ($p in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            $stores = New-Object 'System.Collections.Generic.List[string]'
            try {
                $all = Get-ChildItem $p.PSPath -Recurse -ErrorAction SilentlyContinue
                foreach ($sub in $all) {
                    $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
                    if (-not $props) { continue }
                    foreach ($pn in $props.PSObject.Properties.Name) {
                        if ($pn -eq '001f6700') {
                            $raw = $props.$pn
                            if ($raw -is [byte[]]) {
                                $str = [System.Text.Encoding]::Unicode.GetString($raw) -replace "`0",''
                                if ($str -match '\.(pst|ost)$') { $stores.Add($str) }
                            }
                        }
                    }
                }
            } catch {}
            [PSCustomObject]@{
                Name      = $p.PSChildName
                IsDefault = ($p.PSChildName -eq $defaultProfile)
                Version   = $version
                Stores    = @($stores | Select-Object -Unique)
            }
        }
    }
    return @($profiles)
}

$script:ScanExclusions = @(
    'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData',
    '$Recycle.Bin', 'System Volume Information', 'Recovery'
)

function Get-DriveRoots([string[]]$Override) {
    if ($Override -and $Override.Count -gt 0) {
        return @($Override | ForEach-Object { $d = $_.TrimEnd(':','\','/'); "${d}:\" })
    }
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[A-Z]$' -and $null -ne $_.Used }
    return @($drives | ForEach-Object { "$($_.Name):\" })
}

function Find-DataFiles {
    param([string[]]$Roots, [bool]$IncludeOstFlag)
    $patterns = if ($IncludeOstFlag) { @('*.pst','*.ost') } else { @('*.pst') }
    $found = New-Object 'System.Collections.Generic.List[object]'
    foreach ($root in $Roots) {
        if (-not (Test-Path $root)) { continue }
        Write-Host "  [*] Scanning $root for Outlook data files..." -ForegroundColor Magenta
        $topLevel = Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $script:ScanExclusions -notcontains $_.Name }
        foreach ($pat in $patterns) {
            Get-ChildItem -LiteralPath $root -Filter $pat -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $found.Add($_) }
        }
        foreach ($dir in $topLevel) {
            foreach ($pat in $patterns) {
                try {
                    Get-ChildItem -LiteralPath $dir.FullName -Filter $pat -Recurse -File -Force -ErrorAction SilentlyContinue |
                        ForEach-Object { $found.Add($_) }
                } catch {}
            }
        }
    }
    $now = Get-Date
    $rows = foreach ($f in $found) {
        $daysMod = [math]::Round(($now - $f.LastWriteTime).TotalDays, 0)
        $daysAcc = $null
        try { if ($f.LastAccessTime) { $daysAcc = [math]::Round(($now - $f.LastAccessTime).TotalDays, 0) } } catch {}
        [PSCustomObject]@{
            FullPath          = $f.FullName
            Name              = $f.Name
            Extension         = $f.Extension.ToLower()
            Bytes             = $f.Length
            Size              = Format-Bytes $f.Length
            LastModified      = $f.LastWriteTime.ToString('yyyy-MM-dd')
            DaysSinceModified = $daysMod
            DaysSinceAccessed = $daysAcc
        }
    }
    return @($rows | Sort-Object Bytes -Descending)
}

function Add-ProfileAttachment([array]$Files, [array]$Profiles) {
    $map = @{}
    foreach ($p in $Profiles) {
        foreach ($s in $p.Stores) {
            $key = $s.ToLower()
            if (-not $map.ContainsKey($key)) { $map[$key] = New-Object 'System.Collections.Generic.List[string]' }
            [void]$map[$key].Add($p.Name)
        }
    }
    foreach ($f in $Files) {
        $attached = @()
        if ($map.ContainsKey($f.FullPath.ToLower())) { $attached = $map[$f.FullPath.ToLower()] }
        $f | Add-Member -NotePropertyName 'AttachedTo' -NotePropertyValue (@($attached) -join ', ') -Force
        $f | Add-Member -NotePropertyName 'IsOrphaned' -NotePropertyValue ($attached.Count -eq 0)    -Force
    }
    return $Files
}

function Get-VaultVerdict([array]$Files) {
    $issues = @(); $warns = @()
    $psts     = @($Files | Where-Object { $_.Extension -eq '.pst' })
    $orphaned = @($Files | Where-Object { $_.IsOrphaned -and $_.Extension -eq '.pst' })
    $oversize = @($Files | Where-Object { $_.Extension -eq '.pst' -and $_.Bytes -ge 50GB })
    $large    = @($Files | Where-Object { $_.Extension -eq '.pst' -and $_.Bytes -ge 10GB -and $_.Bytes -lt 50GB })
    $stale    = @($Files | Where-Object { $_.Extension -eq '.pst' -and $_.DaysSinceAccessed -and $_.DaysSinceAccessed -ge 365 })

    if ($orphaned.Count -gt 0) { $warns  += "$($orphaned.Count) PST(s) on disk are not attached to any Outlook profile -- review whether each should be ingested or deleted." }
    foreach ($f in $oversize)   { $issues += "PST '$($f.FullPath)' is $($f.Size) -- Exchange Online Import Service has a 50 GB hard limit per file; split before ingest." }
    if ($large.Count -gt 0)     { $warns  += "$($large.Count) PST(s) are 10-50 GB -- migrations will be slow; consider splitting or ingesting overnight." }
    if ($stale.Count -gt 0)     { $warns  += "$($stale.Count) PST(s) have not been accessed in 365+ days -- candidates for archive-on-ingest rather than primary-mailbox import." }
    if ($psts.Count -eq 0)      { $warns  += "No PSTs found on disk -- either already migrated or never existed on this machine." }

    $verdict = if ($issues.Count -gt 0) { 'ACTION REQUIRED' } elseif ($warns.Count -gt 0) { 'REVIEW BEFORE MIGRATION' } else { 'READY TO MIGRATE' }
    $class   = if ($issues.Count -gt 0) { 'crit' }            elseif ($warns.Count -gt 0) { 'warn' }                  else { 'ok' }
    $totalSum = ($psts | Measure-Object -Property Bytes -Sum).Sum
    if (-not $totalSum) { $totalSum = 0 }
    return [PSCustomObject]@{
        Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns)
        PstCount = $psts.Count; Orphans = $orphaned.Count
        Oversize = $oversize.Count; Large = $large.Count; Stale = $stale.Count
        TotalPstBytes = [long]$totalSum
    }
}

# ===========================
# RUN
# ===========================

$roots = Get-DriveRoots -Override $DrivesArr
if ($roots.Count -eq 0) {
    Write-Host "[ERROR] No local drives detected to scan." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Reading Outlook profiles..." -ForegroundColor Magenta
$profiles = Get-OutlookProfiles
Write-Host ("[OK] Profiles found: {0}" -f $profiles.Count) -ForegroundColor Green
foreach ($p in $profiles) {
    $tag = if ($p.IsDefault) { '[DEFAULT]' } else { '' }
    Write-Host "  $($p.Name) $tag  ($($p.Version))" -ForegroundColor Cyan
    if ($p.Stores.Count -eq 0) {
        Write-Host "    (no attached stores)" -ForegroundColor Gray
    } else {
        foreach ($s in $p.Stores) { Write-Host "    * $s" -ForegroundColor Gray }
    }
}
Write-Host ""

Write-Host "[*] Scanning drives: $($roots -join ', ')" -ForegroundColor Magenta
$files = Find-DataFiles -Roots $roots -IncludeOstFlag:$IncludeOst
$files = Add-ProfileAttachment -Files $files -Profiles $profiles
$verdict = Get-VaultVerdict -Files $files

Write-Host ""
Write-Host "[OK] $($files.Count) Outlook data file(s) found." -ForegroundColor Green
foreach ($f in $files | Select-Object -First 30) {
    $color = if ($f.Bytes -ge 50GB) { 'Red' }
             elseif ($f.Bytes -ge 10GB) { 'Yellow' }
             elseif ($f.IsOrphaned) { 'Yellow' }
             else { 'Gray' }
    $tag = if ($f.IsOrphaned) { '[ORPHAN]' } else { "[$($f.AttachedTo)]" }
    Write-Host ("  {0,10}  {1}  {2}" -f $f.Size, $f.FullPath, $tag) -ForegroundColor $color
}
if ($files.Count -gt 30) {
    Write-Host "  ... and $($files.Count - 30) more (see HTML report)." -ForegroundColor Gray
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MIGRATION READINESS VERDICT" -ForegroundColor Cyan
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

$profileRows = ""
if ($profiles.Count -eq 0) {
    $profileRows = "<tr><td colspan='4' style='text-align:center;color:#aaa;'>No Outlook profiles configured for the current user.</td></tr>"
} else {
    foreach ($p in $profiles) {
        $defBadge = if ($p.IsDefault) { "<span class='badge badge-ok'>Default</span>" } else { "<span class='badge badge-neutral'>Secondary</span>" }
        $storeList = if ($p.Stores.Count -gt 0) { ($p.Stores | ForEach-Object { "<code>$(HtmlEncode $_)</code>" }) -join '<br>' } else { "<span class='badge badge-neutral'>(none)</span>" }
        $profileRows += "<tr><td><strong>$(HtmlEncode $p.Name)</strong></td><td>$defBadge</td><td>$(HtmlEncode $p.Version)</td><td>$storeList</td></tr>"
    }
}

$fileRows = ""
if ($files.Count -eq 0) {
    $fileRows = "<tr><td colspan='6' style='text-align:center;color:#2ecc71;'>No Outlook data files found on the scanned drives.</td></tr>"
} else {
    foreach ($f in $files) {
        $sizeClass = if ($f.Bytes -ge 50GB) { 'badge-crit' }
                     elseif ($f.Bytes -ge 10GB) { 'badge-warn' }
                     elseif ($f.Bytes -ge 1GB)  { 'badge-neutral' }
                     else { 'badge-ok' }
        $orphanCell = if ($f.IsOrphaned) { "<span class='badge badge-warn'>Orphaned</span>" } else { "<span class='badge badge-ok'>$(HtmlEncode $f.AttachedTo)</span>" }
        $extCell    = if ($f.Extension -eq '.ost') { "<span class='badge badge-neutral'>OST</span>" } else { "<span class='badge badge-ok'>PST</span>" }
        $daysAcc    = if ($null -ne $f.DaysSinceAccessed) { "$($f.DaysSinceAccessed)" } else { '-' }
        $fileRows += "<tr><td><code>$(HtmlEncode $f.FullPath)</code></td><td>$extCell</td><td><span class='badge $sizeClass'>$(HtmlEncode $f.Size)</span></td><td>$(HtmlEncode $f.LastModified)</td><td>$orphanCell</td><td>$daysAcc</td></tr>"
    }
}

$verdictBlock = ""
foreach ($i in $verdict.Issues) { $verdictBlock += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $verdictBlock += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $verdictBlock = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>All pre-migration checks passed.</li>"
}

$scopeLabel = "$($roots -join ', ') ($(if ($IncludeOst) { 'PST + OST' } else { 'PST only' }))"
$totalPstSize = Format-Bytes $verdict.TotalPstBytes

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>V.A.U.L.T. PST Discovery -- $env:COMPUTERNAME</title>
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
<h1>V.A.U.L.T. -- Outlook PST / OST Discovery</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Run As: $env:USERDOMAIN\$env:USERNAME &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Scope: $scopeLabel</div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Migration Readiness</div></div>
  <div class="card"><div class="val">$($verdict.PstCount)</div><div class="lbl">PST Files Found</div></div>
  <div class="card"><div class="val">$totalPstSize</div><div class="lbl">Total PST Size</div></div>
  <div class="card $(if ($verdict.Orphans -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($verdict.Orphans)</div><div class="lbl">Orphaned</div></div>
  <div class="card $(if ($verdict.Oversize -gt 0) { 'crit' } else { 'ok' })"><div class="val">$($verdict.Oversize)</div><div class="lbl">Over 50 GB</div></div>
  <div class="card $(if ($verdict.Stale -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($verdict.Stale)</div><div class="lbl">Stale (&gt;365d)</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$verdictBlock</ul>

<div class="section-title">Outlook Profiles ($($profiles.Count))</div>
<table>
  <thead><tr><th>Profile</th><th>Default</th><th>Version</th><th>Attached Stores</th></tr></thead>
  <tbody>$profileRows</tbody>
</table>

<div class="section-title">Data Files ($($files.Count))</div>
<table>
  <thead><tr><th>Path</th><th>Type</th><th>Size</th><th>Last Modified</th><th>Attached To</th><th>Days Since Last Access</th></tr></thead>
  <tbody>$fileRows</tbody>
</table>

<div class="footer">
  Generated by V.A.U.L.T. -- Technician Toolkit LiveConnect Suite. Reads HKCU Outlook profiles for the running user.
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
Write-Host "[OK] V.A.U.L.T. complete." -ForegroundColor Cyan
Write-Host ""
