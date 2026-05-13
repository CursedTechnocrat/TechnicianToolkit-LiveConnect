<#
.SYNOPSIS
    P.U.L.S.E. — Physical-disk Usage, Lifespan & SMART Evaluation
    LiveConnect-Compatible Disk Health & SMART Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Inspects every physical disk in the system: health status, operational
    state, SMART failure prediction, serial/firmware, bus & media type, and
    volume capacity. Flags drives that report degraded health or predicted
    failures. Exports a dark-themed HTML report to the specified path.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\pulse.ps1
    PS C:\> .\pulse.ps1 -ReportPath "C:\Temp"
    PS C:\> .\pulse.ps1 -ReportPath "\\server\share\Reports"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Folder  : LiveConnect/
    Target  : Kaseya VSA LiveConnect terminal
    Mirrors : A.U.G.U.R. (main toolkit)

    Color Schema
    ─────────────────────────────────────────
    Cyan     Headers and section dividers
    Green    Success messages
    Yellow   Warnings
    Red      Errors
    Gray     Info and detail lines
#>

param(
    [string]$ReportPath = "C:\Temp"
)

# ===========================
# ADMIN CHECK
# ===========================

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===========================
# HEADER
# ===========================

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "PULSE_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  P.U.L.S.E. -- Physical-disk Usage, Lifespan & SMART Evaluation" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As    : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time      : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Report    : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

# ===========================
# DATA COLLECTION
# ===========================

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

Write-Host "[*] Reading physical disk health..." -ForegroundColor Magenta

$diskReport = @()

try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop

    # SMART failure prediction via WMI
    $smartData = @()
    try {
        $smartData = @(Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue)
    } catch {}

    # Win32_DiskDrive for serial/firmware
    $wmiDisks = @{}
    try {
        Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
            $wmiDisks[[string]$_.Index] = $_
        }
    } catch {}

    foreach ($pd in $physDisks) {
        $sizeGB = if ($pd.Size -gt 0) { [math]::Round($pd.Size / 1GB, 1) } else { 0 }

        $smartEntry  = $smartData | Where-Object { $_.InstanceName -match [regex]::Escape($pd.DeviceId) } | Select-Object -First 1
        $smartFail   = if ($smartEntry) { $smartEntry.PredictFailure } else { $null }
        $smartReason = if ($smartEntry -and $smartEntry.Reason) { "0x{0:X8}" -f $smartEntry.Reason } else { 'N/A' }

        $wmiDisk   = $wmiDisks[[string]$pd.DeviceId]
        $serial    = if ($wmiDisk -and $wmiDisk.SerialNumber) { $wmiDisk.SerialNumber.Trim() } else { 'N/A' }
        $firmware  = if ($wmiDisk -and $wmiDisk.FirmwareRevision) { $wmiDisk.FirmwareRevision.Trim() } else { 'N/A' }

        $smartLabel = if ($null -eq $smartFail)        { 'N/A' }
                      elseif ($smartFail -eq $false)   { 'OK' }
                      else                             { 'FAILING' }

        $lineColor = if ($smartFail -eq $true -or ($pd.HealthStatus -and $pd.HealthStatus -notin 'Healthy','Warning')) {
            'Red'
        } elseif ($pd.HealthStatus -eq 'Warning') {
            'Yellow'
        } else {
            'Green'
        }

        Write-Host ("  [{0}] {1} | {2} {3} | {4} GB | Health: {5} | SMART: {6}" -f `
            $pd.DeviceId, $pd.FriendlyName, $pd.MediaType, $pd.BusType, $sizeGB, $pd.HealthStatus, $smartLabel) `
            -ForegroundColor $lineColor

        $diskReport += [PSCustomObject]@{
            ID                = $pd.DeviceId
            Name              = $pd.FriendlyName
            Serial            = $serial
            Firmware          = $firmware
            MediaType         = "$($pd.MediaType)"
            BusType           = "$($pd.BusType)"
            SizeGB            = $sizeGB
            HealthStatus      = "$($pd.HealthStatus)"
            OperationalStatus = ($pd.OperationalStatus -join ', ')
            SMARTPrediction   = $smartLabel
            SMARTReason       = $smartReason
        }
    }

    Write-Host ""
    Write-Host "[OK] $($diskReport.Count) physical disk(s) assessed." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Reading physical disks: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "[*] Reading volume health..." -ForegroundColor Magenta

$volumeReport = @()

try {
    $volumes = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -or $_.FileSystemLabel }

    foreach ($vol in $volumes) {
        $totalGB = if ($vol.Size -gt 0) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }
        $freeGB  = if ($vol.SizeRemaining -gt 0) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { 0 }
        $pct     = if ($vol.Size -gt 0) { [math]::Round(($vol.Size - $vol.SizeRemaining) / $vol.Size * 100, 1) } else { 0 }

        $volColor = switch ($vol.HealthStatus) {
            'Healthy' { 'Green' }
            'Warning' { 'Yellow' }
            default   { 'Red'   }
        }
        if ($pct -ge 90) { $volColor = 'Red' } elseif ($pct -ge 75 -and $volColor -eq 'Green') { $volColor = 'Yellow' }

        $label  = if ($vol.DriveLetter)      { "$($vol.DriveLetter):" } else { "(no letter)" }
        $fsLabel = if ($vol.FileSystemLabel) { $vol.FileSystemLabel }   else { "" }

        Write-Host ("  {0,-6} {1,-20} {2,7} GB total  {3,7} GB free  {4,5}%  [{5}]" -f `
            $label, $fsLabel, $totalGB, $freeGB, $pct, $vol.HealthStatus) -ForegroundColor $volColor

        $volumeReport += [PSCustomObject]@{
            Drive       = $label
            Label       = $fsLabel
            FileSystem  = "$($vol.FileSystem)"
            TotalGB     = $totalGB
            FreeGB      = $freeGB
            PctUsed     = $pct
            Health      = "$($vol.HealthStatus)"
            DriveType   = "$($vol.DriveType)"
        }
    }

    Write-Host ""
    Write-Host "[OK] $($volumeReport.Count) volume(s) assessed." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Reading volumes: $($_.Exception.Message)" -ForegroundColor Red
}

# ===========================
# HTML REPORT
# ===========================

Write-Host ""
Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$healthyCount   = ($diskReport | Where-Object { $_.HealthStatus -eq 'Healthy' -and $_.SMARTPrediction -ne 'FAILING' } | Measure-Object).Count
$warningCount   = ($diskReport | Where-Object { $_.HealthStatus -eq 'Warning' } | Measure-Object).Count
$criticalCount  = ($diskReport | Where-Object { $_.HealthStatus -ne 'Healthy' -and $_.HealthStatus -ne 'Warning' -and $_.HealthStatus } | Measure-Object).Count
$smartFailCount = ($diskReport | Where-Object { $_.SMARTPrediction -eq 'FAILING' } | Measure-Object).Count

$diskRows = ""
foreach ($d in $diskReport) {
    $hBadge = switch ($d.HealthStatus) {
        'Healthy' { 'badge-ok' } 'Warning' { 'badge-warn' } default { 'badge-crit' }
    }
    $sBadge = if ($d.SMARTPrediction -eq 'FAILING') { 'badge-crit' } elseif ($d.SMARTPrediction -eq 'OK') { 'badge-ok' } else { 'badge-neutral' }

    $diskRows += @"
        <tr>
            <td><strong>$(HtmlEncode($d.ID))</strong></td>
            <td>$(HtmlEncode($d.Name))</td>
            <td><code>$(HtmlEncode($d.Serial))</code></td>
            <td>$(HtmlEncode($d.MediaType))</td>
            <td>$(HtmlEncode($d.BusType))</td>
            <td>$($d.SizeGB) GB</td>
            <td><span class='badge $hBadge'>$(HtmlEncode($d.HealthStatus))</span></td>
            <td>$(HtmlEncode($d.OperationalStatus))</td>
            <td><span class='badge $sBadge'>$(HtmlEncode($d.SMARTPrediction))</span></td>
            <td><code>$(HtmlEncode($d.SMARTReason))</code></td>
            <td>$(HtmlEncode($d.Firmware))</td>
        </tr>
"@
}

$volumeRows = ""
foreach ($v in $volumeReport) {
    $barBadge = if ($v.PctUsed -ge 90) { 'badge-crit' } elseif ($v.PctUsed -ge 75) { 'badge-warn' } else { 'badge-ok' }
    $vhBadge  = switch ($v.Health) { 'Healthy' { 'badge-ok' } 'Warning' { 'badge-warn' } default { 'badge-crit' } }
    $volumeRows += @"
        <tr>
            <td><code>$(HtmlEncode($v.Drive))</code></td>
            <td>$(HtmlEncode($v.Label))</td>
            <td>$(HtmlEncode($v.FileSystem))</td>
            <td>$($v.TotalGB) GB</td>
            <td>$($v.FreeGB) GB</td>
            <td><span class='badge $barBadge'>$($v.PctUsed)%</span></td>
            <td><span class='badge $vhBadge'>$(HtmlEncode($v.Health))</span></td>
        </tr>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>P.U.L.S.E. Disk Health -- $env:COMPUTERNAME</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', Consolas, monospace; font-size: 14px; padding: 24px; }
  h1 { color: #00d4ff; font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 24px; }
  .summary { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 28px; }
  .card { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 16px 24px; min-width: 120px; text-align: center; }
  .card .val { font-size: 28px; font-weight: bold; color: #00d4ff; }
  .card .lbl { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-top: 4px; }
  .card.warn .val { color: #f39c12; }
  .card.crit .val { color: #e74c3c; }
  .card.ok   .val { color: #2ecc71; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th { background: #0f3460; color: #00d4ff; padding: 10px 12px; text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
  td { padding: 9px 12px; border-bottom: 1px solid #1e2d4d; vertical-align: top; }
  tr:hover td { background: #1e2d4d; }
  code { background: #0f1928; padding: 1px 6px; border-radius: 3px; font-size: 12px; color: #00d4ff; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; }
  .badge-ok      { background: #1a4a2e; color: #2ecc71; }
  .badge-warn    { background: #4a3a10; color: #f39c12; }
  .badge-crit    { background: #4a1a1a; color: #e74c3c; }
  .badge-neutral { background: #2a2a3e; color: #aaa; }
  .section-title { color: #00d4ff; font-size: 15px; margin: 28px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>P.U.L.S.E. -- Disk Health &amp; SMART Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card ok"><div class="val">$healthyCount</div><div class="lbl">Healthy</div></div>
  <div class="card warn"><div class="val">$warningCount</div><div class="lbl">Warning</div></div>
  <div class="card crit"><div class="val">$criticalCount</div><div class="lbl">Critical</div></div>
  <div class="card crit"><div class="val">$smartFailCount</div><div class="lbl">SMART Fail</div></div>
  <div class="card"><div class="val">$($volumeReport.Count)</div><div class="lbl">Volumes</div></div>
</div>

<div class="section-title">Physical Disks ($($diskReport.Count))</div>
<table>
  <thead>
    <tr>
      <th>ID</th><th>Name</th><th>Serial</th><th>Type</th><th>Bus</th>
      <th>Size</th><th>Health</th><th>Status</th><th>SMART</th><th>SMART Reason</th><th>Firmware</th>
    </tr>
  </thead>
  <tbody>
    $diskRows
  </tbody>
</table>

<div class="section-title">Volumes ($($volumeReport.Count))</div>
<table>
  <thead>
    <tr>
      <th>Drive</th><th>Label</th><th>File System</th><th>Total</th><th>Free</th><th>Usage</th><th>Health</th>
    </tr>
  </thead>
  <tbody>
    $volumeRows
  </tbody>
</table>

<div class="footer">
  Generated by P.U.L.S.E. -- Technician Toolkit LiveConnect Suite
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

# ===========================
# SUMMARY
# ===========================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  P.U.L.S.E. SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Physical Disks : $($diskReport.Count)" -ForegroundColor Gray
Write-Host "  Volumes        : $($volumeReport.Count)" -ForegroundColor Gray
Write-Host "  Healthy        : $healthyCount" -ForegroundColor Green
Write-Host "  Warnings       : $warningCount" -ForegroundColor $(if ($warningCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Critical       : $criticalCount" -ForegroundColor $(if ($criticalCount  -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  SMART Failing  : $smartFailCount" -ForegroundColor $(if ($smartFailCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] P.U.L.S.E. complete." -ForegroundColor Cyan
Write-Host ""
