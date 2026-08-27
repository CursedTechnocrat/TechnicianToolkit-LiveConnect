# verge.ps1 - V.E.R.G.E. — Volume Examination & Resource Gauge Evaluator
# Part of the Technician Toolkit - https://github.com/CursedTechnocrat/TechnicianToolkit-LiveConnect
#
# Copyright (C) 2026 CursedTechnocrat and the Technician Toolkit contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    V.E.R.G.E. — Volume Examination & Resource Gauge Evaluator
    LiveConnect-Compatible Disk Space & Stale Profile Audit for PowerShell 5.1+

.DESCRIPTION
    Read-only disk and storage assessment: physical-disk health (Get-PhysicalDisk
    + Win32_DiskDrive), per-volume capacity with low-space flags (Warning < 15%
    free, Critical < 5%), and detection of stale user profiles under C:\Users
    that haven't been touched in N days. Exports a dark-themed HTML report
    with progress bars and recommendations.

    For actual cleanup, use the companion P.U.R.G.E. script — V.E.R.G.E. is
    audit-only and modifies no state.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

.USAGE
    PS C:\> .\verge.ps1
    PS C:\> .\verge.ps1 -ReportPath "C:\Temp"
    PS C:\> .\verge.ps1 -StaleProfileDays 60

.PARAMETERS
    -ReportPath         Folder where the HTML report is saved (default: C:\Temp)
    -StaleProfileDays   Days of profile inactivity that flag a user as stale (default: 90)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : T.H.R.E.S.H.O.L.D. (main toolkit, audit-only subset)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [ValidateRange(1, 3650)] [int]$StaleProfileDays = 90
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "VERGE_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  V.E.R.G.E. -- Volume Examination & Resource Gauge Evaluator" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine            : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As             : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time               : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Stale profile days : $StaleProfileDays" -ForegroundColor Gray
Write-Host "  Report             : $reportFullPath" -ForegroundColor Gray
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

function Get-PhysicalDiskInfo {
    $physDisks   = Get-PhysicalDisk -ErrorAction SilentlyContinue
    $diskObjects = Get-Disk        -ErrorAction SilentlyContinue
    $cimDisks    = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue

    $results = @()
    foreach ($pd in $physDisks) {
        $matchedDisk = $diskObjects | Where-Object { $_.Number -eq ($pd.DeviceId -replace '\D','') } | Select-Object -First 1
        if (-not $matchedDisk) { $matchedDisk = $diskObjects | Where-Object { $_.Size -eq $pd.Size } | Select-Object -First 1 }
        $cimMatch = $cimDisks | Where-Object { $_.Size -eq $pd.Size } | Select-Object -First 1

        $results += [PSCustomObject]@{
            FriendlyName      = "$($pd.FriendlyName)"
            MediaType         = "$($pd.MediaType)"
            Size              = $pd.Size
            SizeFormatted     = Format-Bytes ([long]$pd.Size)
            HealthStatus      = if ($pd.HealthStatus) { "$($pd.HealthStatus)" } else { 'Unknown' }
            OperationalStatus = if ($pd.OperationalStatus) { ($pd.OperationalStatus -join ', ') }
                                elseif ($cimMatch) { $cimMatch.Status } else { 'Unknown' }
            BusType           = "$($pd.BusType)"
            DiskNumber        = if ($matchedDisk) { $matchedDisk.Number } else { 'N/A' }
            PartitionStyle    = if ($matchedDisk) { "$($matchedDisk.PartitionStyle)" } else { 'N/A' }
            IsSystem          = if ($matchedDisk) { [bool]$matchedDisk.IsSystem } else { $false }
            IsBoot            = if ($matchedDisk) { [bool]$matchedDisk.IsBoot } else { $false }
        }
    }
    return $results
}

function Get-VolumeInfo {
    $volumes = Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveType -ne 'CD-ROM' -and $null -ne $_.DriveLetter -and $_.Size -gt 0
    }
    $results = @()
    foreach ($vol in $volumes) {
        $pctFree     = if ($vol.Size -gt 0) { [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1) } else { 0 }
        $spaceStatus = if ($pctFree -lt 5) { 'Critical' } elseif ($pctFree -lt 15) { 'Warning' } else { 'OK' }
        $results += [PSCustomObject]@{
            DriveLetter   = $vol.DriveLetter
            Label         = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { '(No Label)' }
            FileSystem    = "$($vol.FileSystem)"
            Size          = $vol.Size
            SizeFormatted = Format-Bytes ([long]$vol.Size)
            SizeRemaining = $vol.SizeRemaining
            FreeFormatted = Format-Bytes ([long]$vol.SizeRemaining)
            PercentFree   = $pctFree
            SpaceStatus   = $spaceStatus
            DriveType     = "$($vol.DriveType)"
            HealthStatus  = if ($vol.HealthStatus) { "$($vol.HealthStatus)" } else { 'Unknown' }
        }
    }
    return $results
}

function Get-StaleProfiles {
    param([int]$Days)
    $usersRoot = 'C:\Users'
    if (-not (Test-Path $usersRoot)) { return @() }
    $cutoff   = (Get-Date).AddDays(-$Days)
    $excluded = @('Public','Default','Default User','All Users','defaultuser0')

    $rows = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $excluded -and $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            $sizeBytes = 0L
            try {
                $sum = (Get-ChildItem -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sum) { $sizeBytes = [long]$sum }
            } catch {}
            [PSCustomObject]@{
                Name          = $_.Name
                Path          = $_.FullName
                LastWriteTime = $_.LastWriteTime
                AgeDays       = [math]::Round(((Get-Date) - $_.LastWriteTime).TotalDays)
                SizeBytes     = $sizeBytes
                SizeFormatted = Format-Bytes $sizeBytes
            }
        }
    return @($rows)
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Collecting physical disk data..." -ForegroundColor Magenta
$diskData = Get-PhysicalDiskInfo
foreach ($d in $diskData) {
    $hColor = switch ($d.HealthStatus) { 'Healthy' { 'Green' } 'Warning' { 'Yellow' } 'Unhealthy' { 'Red' } default { 'Gray' } }
    $flag   = if ($d.IsBoot) { '[BOOT]' } elseif ($d.IsSystem) { '[SYS]' } else { '' }
    Write-Host ("  Disk {0}: {1} ({2}) {3,-10} Health: {4} {5}" -f $d.DiskNumber, $d.FriendlyName, $d.MediaType, $d.SizeFormatted, $d.HealthStatus, $flag) -ForegroundColor $hColor
}
Write-Host ""

Write-Host "[*] Collecting volume data..." -ForegroundColor Magenta
$volData = Get-VolumeInfo
foreach ($v in $volData) {
    $sColor = switch ($v.SpaceStatus) { 'Critical' { 'Red' } 'Warning' { 'Yellow' } default { 'Green' } }
    $bar    = if ($v.PercentFree -ge 100) { 100 } else { [int]$v.PercentFree }
    $barStr = '[' + ('#' * [math]::Round($bar / 5)) + ('.' * (20 - [math]::Round($bar / 5))) + ']'
    Write-Host ("  {0,-4} {1,-20} {2,7} total {3,7} free  {4,5}%  {5}  [{6}]" -f `
        "$($v.DriveLetter):", $v.Label, $v.SizeFormatted, $v.FreeFormatted, $v.PercentFree, $barStr, $v.SpaceStatus) -ForegroundColor $sColor
}
Write-Host ""

Write-Host "[*] Detecting stale user profiles (> $StaleProfileDays days)..." -ForegroundColor Magenta
$profiles = Get-StaleProfiles -Days $StaleProfileDays
if ($profiles.Count -eq 0) {
    Write-Host "[OK] No user profiles older than $StaleProfileDays days." -ForegroundColor Green
} else {
    foreach ($p in $profiles) {
        Write-Host ("  {0,-22} last write {1} ({2} days)  size {3}" -f $p.Name, $p.LastWriteTime.ToString('yyyy-MM-dd'), $p.AgeDays, $p.SizeFormatted) -ForegroundColor Yellow
    }
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$totalDrives  = $diskData.Count
$healthyCount = ($diskData | Where-Object { $_.HealthStatus -eq 'Healthy' } | Measure-Object).Count
$warnCount    = ($diskData | Where-Object { $_.HealthStatus -notin @('Healthy','Unknown') } | Measure-Object).Count
$totalStorage = ($volData | Measure-Object -Property Size -Sum).Sum
$totalFree    = ($volData | Measure-Object -Property SizeRemaining -Sum).Sum
$totalStorage = if ($totalStorage) { [long]$totalStorage } else { 0 }
$totalFree    = if ($totalFree)    { [long]$totalFree }    else { 0 }

$diskRows = ""
foreach ($d in $diskData) {
    $badgeClass = switch ($d.HealthStatus) { 'Healthy' { 'badge-ok' } 'Warning' { 'badge-warn' } 'Unhealthy' { 'badge-crit' } default { 'badge-neutral' } }
    $bootTag = if ($d.IsBoot) { " <span class='badge badge-neutral'>BOOT</span>" } else { '' }
    $diskRows += @"
        <tr>
            <td>$(HtmlEncode $d.FriendlyName)$bootTag</td>
            <td>$(HtmlEncode $d.MediaType)</td>
            <td>$(HtmlEncode $d.SizeFormatted)</td>
            <td><span class='badge $badgeClass'>$(HtmlEncode $d.HealthStatus)</span></td>
            <td>$(HtmlEncode $d.OperationalStatus)</td>
            <td>$(HtmlEncode $d.BusType)</td>
            <td>$(HtmlEncode $d.PartitionStyle)</td>
        </tr>
"@
}

$volRows = ""
foreach ($v in $volData) {
    $statusClass = switch ($v.SpaceStatus) { 'Critical' { 'badge-crit' } 'Warning' { 'badge-warn' } default { 'badge-ok' } }
    $barColor    = switch ($v.SpaceStatus) { 'Critical' { '#e74c3c' }   'Warning' { '#f39c12' }   default { '#2ecc71' } }
    $barWidth    = [math]::Min(100, [math]::Max(1, [int]$v.PercentFree))
    $volRows += @"
        <tr>
            <td><strong>$($v.DriveLetter):</strong></td>
            <td>$(HtmlEncode $v.Label)</td>
            <td>$(HtmlEncode $v.FileSystem)</td>
            <td>$(HtmlEncode $v.SizeFormatted)</td>
            <td>$(HtmlEncode $v.FreeFormatted)</td>
            <td>
                <div style='background:#0f1928;border-radius:4px;height:14px;width:140px;overflow:hidden;display:inline-block;vertical-align:middle;'>
                    <div style='background:$barColor;height:14px;width:$($barWidth)%;'></div>
                </div>
                <code style='margin-left:6px;'>$($v.PercentFree)%</code>
            </td>
            <td><span class='badge $statusClass'>$($v.SpaceStatus)</span></td>
            <td>$(HtmlEncode $v.HealthStatus)</td>
        </tr>
"@
}

$profileRows = ""
if ($profiles.Count -eq 0) {
    $profileRows = "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No user profiles older than $StaleProfileDays days.</td></tr>"
} else {
    foreach ($p in ($profiles | Sort-Object SizeBytes -Descending)) {
        $profileRows += "<tr><td><strong>$(HtmlEncode $p.Name)</strong></td><td>$(HtmlEncode $p.LastWriteTime.ToString('yyyy-MM-dd'))</td><td>$($p.AgeDays) days</td><td>$(HtmlEncode $p.SizeFormatted)</td></tr>"
    }
}

$recommendations = ""
$critVols = $volData | Where-Object { $_.SpaceStatus -eq 'Critical' }
$warnVols = $volData | Where-Object { $_.SpaceStatus -eq 'Warning' }
$badDisks = $diskData | Where-Object { $_.HealthStatus -notin @('Healthy','Unknown') }
foreach ($v in $critVols) {
    $recommendations += "<li class='badge badge-crit' style='display:block;margin:6px 0;padding:8px 12px;'><strong>CRITICAL:</strong> Drive $($v.DriveLetter): ($(HtmlEncode $v.Label)) is critically low on space ($($v.PercentFree)% free).</li>"
}
foreach ($v in $warnVols) {
    $recommendations += "<li class='badge badge-warn' style='display:block;margin:6px 0;padding:8px 12px;'><strong>WARNING:</strong> Drive $($v.DriveLetter): ($(HtmlEncode $v.Label)) has low free space ($($v.PercentFree)% free).</li>"
}
foreach ($d in $badDisks) {
    $recommendations += "<li class='badge badge-crit' style='display:block;margin:6px 0;padding:8px 12px;'><strong>DISK ALERT:</strong> $(HtmlEncode $d.FriendlyName) reports Health Status: $(HtmlEncode $d.HealthStatus). Back up data.</li>"
}
if ($profiles.Count -gt 0) {
    $totalProfileBytes = ($profiles | Measure-Object -Property SizeBytes -Sum).Sum
    $recommendations += "<li class='badge badge-warn' style='display:block;margin:6px 0;padding:8px 12px;'><strong>STALE PROFILES:</strong> $($profiles.Count) profile(s) inactive > $StaleProfileDays days, totaling $(Format-Bytes ([long]$totalProfileBytes)). Review before deletion.</li>"
}
if (-not $recommendations) {
    $recommendations = "<li class='badge badge-ok' style='display:block;margin:6px 0;padding:8px 12px;'>All monitored disks and volumes are within healthy thresholds.</li>"
}

$warnCountClass = if ($warnCount -gt 0) { 'warn' } else { 'ok' }
$totalProfilesCard = $profiles.Count
$profileClass = if ($profiles.Count -gt 0) { 'warn' } else { 'ok' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>V.E.R.G.E. Disk/Storage -- $env:COMPUTERNAME</title>
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
  td { padding: 9px 12px; border-bottom: 1px solid #1e2d4d; vertical-align: middle; }
  tr:hover td { background: #1e2d4d; }
  code { background: #0f1928; padding: 1px 6px; border-radius: 3px; font-size: 12px; color: #00d4ff; }
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
<h1>V.E.R.G.E. -- Disk &amp; Storage Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card"><div class="val">$totalDrives</div><div class="lbl">Total Drives</div></div>
  <div class="card ok"><div class="val">$healthyCount</div><div class="lbl">Healthy</div></div>
  <div class="card $warnCountClass"><div class="val">$warnCount</div><div class="lbl">Warning/Critical</div></div>
  <div class="card"><div class="val">$(Format-Bytes $totalStorage)</div><div class="lbl">Total Storage</div></div>
  <div class="card"><div class="val">$(Format-Bytes $totalFree)</div><div class="lbl">Free Storage</div></div>
  <div class="card $profileClass"><div class="val">$totalProfilesCard</div><div class="lbl">Stale Profiles</div></div>
</div>

<div class="section-title">Recommendations</div>
<ul>$recommendations</ul>

<div class="section-title">Physical Disks</div>
<table>
  <thead><tr><th>Name</th><th>Type</th><th>Size</th><th>Health</th><th>Operational</th><th>Bus</th><th>Partition Style</th></tr></thead>
  <tbody>$diskRows</tbody>
</table>
<div style="margin-top:12px;color:#aaa;font-size:12px;">
  Health Status is sourced from <code>Get-PhysicalDisk</code> and serves as a proxy for SMART data. For full SMART attribute analysis, see <strong>P.U.L.S.E.</strong> (which adds SMART failure prediction).
</div>

<div class="section-title">Volume Space</div>
<table>
  <thead><tr><th>Drive</th><th>Label</th><th>FS</th><th>Total</th><th>Free</th><th>% Free</th><th>Status</th><th>Health</th></tr></thead>
  <tbody>$volRows</tbody>
</table>

<div class="section-title">Stale User Profiles (&gt; $StaleProfileDays days inactive)</div>
<table>
  <thead><tr><th>Profile</th><th>Last Modified</th><th>Age</th><th>Est. Size</th></tr></thead>
  <tbody>$profileRows</tbody>
</table>

<div class="footer">
  Generated by V.E.R.G.E. -- Technician Toolkit LiveConnect Suite. Cleanup actions: run P.U.R.G.E.
</div>
</body>
</html>
"@

try {
    [System.IO.File]::WriteAllText($reportFullPath, $html, [System.Text.Encoding]::UTF8)
    Write-Host "[OK] Report saved: $reportFullPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Could not save report: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] V.E.R.G.E. complete." -ForegroundColor Cyan
Write-Host ""
