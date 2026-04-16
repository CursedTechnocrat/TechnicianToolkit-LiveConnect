<#
.SYNOPSIS
    P.R.O.B.E. — Performs Rapid Operating-system Baseline Evaluation
    LiveConnect-Compatible System Diagnostic & HTML Report Generator for PowerShell 5.1+

.DESCRIPTION
    Audits the current state of a Windows machine and exports a dark-themed HTML
    report. Collects hardware specs, OS info, network config, uptime, pending
    Windows Updates, installed software, and recent event log errors.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\probe.ps1
    PS C:\> .\probe.ps1 -ReportPath "C:\Temp"
    PS C:\> .\probe.ps1 -ReportPath "\\server\share\Reports"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Folder  : LiveConnect/
    Target  : Kaseya VSA LiveConnect terminal

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

$ExecutionTime    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename   = "PROBE_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# Ensure the report folder exists
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
Write-Host "  P.R.O.B.E. -- Performs Rapid Operating-system Baseline Evaluation" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As    : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time      : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Report    : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

# ===========================
# DATA COLLECTION STORAGE
# ===========================

$reportData = [ordered]@{}

# ===========================
# STEP 1: HARDWARE
# ===========================

Write-Host "[1/7] Collecting hardware info..." -ForegroundColor Magenta

try {
    $cs       = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios     = Get-CimInstance -ClassName Win32_BIOS
    $cpu      = Get-CimInstance -ClassName Win32_Processor
    $ramGB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $disks    = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"

    Write-Host "    Manufacturer : $($cs.Manufacturer)" -ForegroundColor Gray
    Write-Host "    Model        : $($cs.Model)" -ForegroundColor Gray
    Write-Host "    Serial       : $($bios.SerialNumber)" -ForegroundColor Gray
    Write-Host "    CPU          : $($cpu.Name)" -ForegroundColor Gray
    Write-Host "    Cores/Threads: $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads" -ForegroundColor Gray
    Write-Host "    RAM          : $ramGB GB" -ForegroundColor Gray

    $diskSummary = @()
    foreach ($disk in $disks) {
        $totalGB = [math]::Round($disk.Size / 1GB, 1)
        $freeGB  = [math]::Round($disk.FreeSpace / 1GB, 1)
        $usedGB  = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 1)
        $pct     = if ($disk.Size -gt 0) { [math]::Round(($disk.Size - $disk.FreeSpace) / $disk.Size * 100, 1) } else { 0 }

        $dColor = if ($pct -ge 90) { 'Red' } elseif ($pct -ge 75) { 'Yellow' } else { 'Gray' }
        Write-Host "    Disk $($disk.DeviceID)      : $usedGB GB used / $totalGB GB total ($pct% full)" -ForegroundColor $dColor

        $diskSummary += [PSCustomObject]@{
            Drive   = $disk.DeviceID
            Label   = $disk.VolumeName
            TotalGB = $totalGB
            UsedGB  = $usedGB
            FreeGB  = $freeGB
            PctUsed = $pct
        }
    }

    $reportData['Hardware'] = [PSCustomObject]@{
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        Serial       = $bios.SerialNumber
        CPU          = $cpu.Name
        Cores        = $cpu.NumberOfCores
        Threads      = $cpu.NumberOfLogicalProcessors
        RAMGB        = $ramGB
        Disks        = $diskSummary
    }

    Write-Host "[OK] Hardware info collected." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Hardware collection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# STEP 2: OPERATING SYSTEM
# ===========================

Write-Host "[2/7] Collecting OS info..." -ForegroundColor Magenta

try {
    $os        = Get-CimInstance -ClassName Win32_OperatingSystem
    $osVersion = $os.Caption
    $osBuild   = $os.BuildNumber
    $osArch    = $os.OSArchitecture
    $osInstall = $os.InstallDate

    $licenseStatus = "Unknown"
    try {
        $slmgr = & cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
        $licenseLine = $slmgr | Where-Object { $_ -match "License Status" }
        if ($licenseLine) {
            $licenseStatus = ($licenseLine -replace "License Status:\s*", "").Trim()
        }
    }
    catch { $licenseStatus = "Could not query" }

    Write-Host "    OS         : $osVersion" -ForegroundColor Gray
    Write-Host "    Build      : $osBuild ($osArch)" -ForegroundColor Gray
    Write-Host "    Installed  : $(Get-Date $osInstall -Format 'yyyy-MM-dd')" -ForegroundColor Gray

    $actColor = if ($licenseStatus -match "Licensed") { 'Green' } else { 'Yellow' }
    Write-Host "    Activation : $licenseStatus" -ForegroundColor $actColor

    $reportData['OS'] = [PSCustomObject]@{
        Caption      = $osVersion
        Build        = $osBuild
        Architecture = $osArch
        InstallDate  = Get-Date $osInstall -Format 'yyyy-MM-dd'
        Activation   = $licenseStatus
    }

    Write-Host "[OK] OS info collected." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] OS collection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# STEP 3: NETWORK
# ===========================

Write-Host "[3/7] Collecting network configuration..." -ForegroundColor Magenta

try {
    $adapters   = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
    $netSummary = @()

    foreach ($adapter in $adapters) {
        $ip      = ($adapter.IPAddress      | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
        $dns     = ($adapter.DNSServerSearchOrder) -join ', '
        $gateway = ($adapter.DefaultIPGateway) -join ', '

        Write-Host "    Adapter  : $($adapter.Description)" -ForegroundColor Gray
        Write-Host "    IP       : $ip  MAC: $($adapter.MACAddress)  GW: $gateway" -ForegroundColor Gray
        Write-Host "    DNS      : $dns" -ForegroundColor Gray
        Write-Host ""

        $netSummary += [PSCustomObject]@{
            Adapter = $adapter.Description
            IP      = $ip
            MAC     = $adapter.MACAddress
            Gateway = $gateway
            DNS     = $dns
        }
    }

    $reportData['Network'] = $netSummary
    Write-Host "[OK] Network config collected." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Network collection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# STEP 4: SYSTEM HEALTH
# ===========================

Write-Host "[4/7] Collecting system health..." -ForegroundColor Magenta

try {
    $osH      = Get-CimInstance -ClassName Win32_OperatingSystem
    $lastBoot = $osH.LastBootUpTime
    $uptime   = (Get-Date) - $lastBoot
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    Write-Host "    Last Boot : $(Get-Date $lastBoot -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "    Uptime    : $uptimeStr" -ForegroundColor Gray

    $batteryInfo = $null
    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($battery) {
        $charge = $battery.EstimatedChargeRemaining
        $status = switch ($battery.BatteryStatus) {
            1 { "Discharging" } 2 { "AC - Fully Charged" } 3 { "Fully Charged" }
            4 { "Low" } 5 { "Critical" } 6 { "Charging" } 7 { "Charging/High" }
            8 { "Charging/Low" } 9 { "Charging/Critical" } default { "Unknown" }
        }
        $bColor = if ($charge -lt 20) { 'Red' } elseif ($charge -lt 40) { 'Yellow' } else { 'Green' }
        Write-Host "    Battery   : $charge% ($status)" -ForegroundColor $bColor
        $batteryInfo = [PSCustomObject]@{ Charge = $charge; Status = $status }
    }
    else {
        Write-Host "    Battery   : N/A (desktop or not detected)" -ForegroundColor Gray
    }

    $reportData['Health'] = [PSCustomObject]@{
        LastBoot = Get-Date $lastBoot -Format 'yyyy-MM-dd HH:mm:ss'
        Uptime   = $uptimeStr
        Battery  = $batteryInfo
    }

    Write-Host "[OK] System health collected." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Health collection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# STEP 5: PENDING UPDATES
# ===========================

Write-Host "[5/7] Scanning for pending Windows Updates..." -ForegroundColor Magenta
Write-Host "    (This may take a moment)" -ForegroundColor Gray

$pendingUpdates = @()
try {
    $updateSession  = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult   = $updateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    if ($searchResult.Updates.Count -eq 0) {
        Write-Host "[OK] No pending updates found." -ForegroundColor Green
    }
    else {
        Write-Host "[!!] $($searchResult.Updates.Count) pending update(s) found:" -ForegroundColor Yellow
        foreach ($update in $searchResult.Updates) {
            Write-Host "     * $($update.Title)" -ForegroundColor Yellow
            $pendingUpdates += [PSCustomObject]@{
                Title    = $update.Title
                Severity = if ($update.MsrcSeverity) { $update.MsrcSeverity } else { "N/A" }
                KB       = ($update.KBArticleIDs -join ', ')
            }
        }
    }

    $reportData['Updates'] = $pendingUpdates
    Write-Host "[OK] Update scan complete." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Update scan failed: $($_.Exception.Message)" -ForegroundColor Red
    $reportData['Updates'] = @()
}

Write-Host ""

# ===========================
# STEP 6: INSTALLED SOFTWARE
# ===========================

Write-Host "[6/7] Collecting installed software..." -ForegroundColor Magenta

$installedApps = @()
try {
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $regPaths) {
        Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName -ne '' } |
            ForEach-Object {
                $installedApps += [PSCustomObject]@{
                    Name        = $_.DisplayName
                    Version     = if ($_.DisplayVersion) { $_.DisplayVersion } else { "N/A" }
                    Publisher   = if ($_.Publisher)       { $_.Publisher }       else { "N/A" }
                    InstallDate = if ($_.InstallDate)     { $_.InstallDate }     else { "N/A" }
                }
            }
    }

    $installedApps     = $installedApps | Sort-Object Name -Unique
    $reportData['Software'] = $installedApps
    Write-Host "[OK] Found $($installedApps.Count) installed application(s)." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Software collection failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# STEP 7: EVENT LOG
# ===========================

Write-Host "[7/7] Scanning event logs (last 24 hours)..." -ForegroundColor Magenta

$eventSummary = @()
try {
    $since  = (Get-Date).AddHours(-24)
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'System', 'Application'
        Level     = @(1, 2)
        StartTime = $since
    } -ErrorAction SilentlyContinue -MaxEvents 50

    if ($null -eq $events -or $events.Count -eq 0) {
        Write-Host "[OK] No critical/error events in the last 24 hours." -ForegroundColor Green
    }
    else {
        Write-Host "[!!] $($events.Count) error/critical event(s) in the last 24 hours." -ForegroundColor Yellow
        $events | Select-Object -First 10 | ForEach-Object {
            $lvl = if ($_.Level -eq 1) { "CRITICAL" } else { "ERROR" }
            Write-Host "     [$lvl] $(Get-Date $_.TimeCreated -Format 'HH:mm:ss') | $($_.ProviderName)" -ForegroundColor Yellow
        }
        if ($events.Count -gt 10) {
            Write-Host "     ... and $($events.Count - 10) more (see full report)" -ForegroundColor Gray
        }

        $eventSummary = $events | ForEach-Object {
            [PSCustomObject]@{
                Time    = Get-Date $_.TimeCreated -Format 'yyyy-MM-dd HH:mm:ss'
                Level   = if ($_.Level -eq 1) { "Critical" } else { "Error" }
                Source  = $_.ProviderName
                Log     = $_.LogName
                Message = $_.Message.Split([Environment]::NewLine)[0]
                EventID = $_.Id
            }
        }
    }

    $reportData['Events'] = $eventSummary
    Write-Host "[OK] Event log scan complete." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Event log scan failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# HTML REPORT GENERATION
# ===========================

Write-Host "Generating HTML report..." -ForegroundColor Magenta

function ConvertTo-HtmlTable {
    param([array]$Objects, [string]$EmptyMessage = "No data available.")
    if (-not $Objects -or $Objects.Count -eq 0) {
        return "<p class='empty'>$EmptyMessage</p>"
    }
    $headers = $Objects[0].PSObject.Properties.Name
    $html    = "<table><thead><tr>"
    $html   += ($headers | ForEach-Object { "<th>$_</th>" }) -join ""
    $html   += "</tr></thead><tbody>"
    foreach ($row in $Objects) {
        $html += "<tr>"
        foreach ($h in $headers) {
            $val  = $row.$h
            $html += "<td>$([System.Web.HttpUtility]::HtmlEncode($val))</td>"
        }
        $html += "</tr>"
    }
    $html += "</tbody></table>"
    return $html
}

# Disk rows
$diskRows = ""
foreach ($d in $reportData['Hardware'].Disks) {
    $barColor = if ($d.PctUsed -ge 90) { "#e74c3c" } elseif ($d.PctUsed -ge 75) { "#f39c12" } else { "#2ecc71" }
    $diskRows += @"
        <tr>
            <td>$($d.Drive)</td>
            <td>$($d.Label)</td>
            <td>$($d.TotalGB) GB</td>
            <td>$($d.UsedGB) GB</td>
            <td>$($d.FreeGB) GB</td>
            <td>
                <div style='background:#444;border-radius:4px;height:14px;width:100%;'>
                    <div style='background:$barColor;width:$($d.PctUsed)%;height:14px;border-radius:4px;'></div>
                </div>
                $($d.PctUsed)%
            </td>
        </tr>
"@
}

# Network rows
$netRows = ""
foreach ($n in $reportData['Network']) {
    $netRows += "<tr><td>$($n.Adapter)</td><td>$($n.IP)</td><td>$($n.MAC)</td><td>$($n.Gateway)</td><td>$($n.DNS)</td></tr>"
}

$hw     = $reportData['Hardware']
$osRep  = $reportData['OS']
$health = $reportData['Health']

$updateCount = $reportData['Updates'].Count
$updateBadge = if ($updateCount -eq 0) {
    "<span class='badge badge-ok'>Up to date</span>"
} else {
    "<span class='badge badge-warn'>$updateCount pending</span>"
}
$updatesTable = if ($updateCount -gt 0) {
    ConvertTo-HtmlTable -Objects $reportData['Updates'] -EmptyMessage "No pending updates."
} else {
    "<p class='empty'>System is fully up to date.</p>"
}

$eventCount = $reportData['Events'].Count
$eventBadge = if ($eventCount -eq 0) {
    "<span class='badge badge-ok'>Clean</span>"
} else {
    "<span class='badge badge-warn'>$eventCount events</span>"
}

$softwareTable = ConvertTo-HtmlTable -Objects $reportData['Software'] -EmptyMessage "No software found."
$eventsTable   = ConvertTo-HtmlTable -Objects $reportData['Events']   -EmptyMessage "No critical/error events in the last 24 hours."

$htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>P.R.O.B.E. -- $env:COMPUTERNAME -- $ExecutionTime</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #1a1a2e; color: #e0e0e0; font-size: 14px; }
  header { background: linear-gradient(135deg, #0f3460, #16213e); padding: 28px 40px; border-bottom: 3px solid #00d4ff; }
  header h1 { color: #00d4ff; font-size: 2em; letter-spacing: 4px; font-weight: 700; }
  header p  { color: #aaa; margin-top: 6px; font-size: 0.9em; }
  header .meta { display: flex; gap: 30px; margin-top: 14px; flex-wrap: wrap; }
  header .meta span { color: #ccc; font-size: 0.85em; }
  header .meta strong { color: #00d4ff; }
  main { padding: 30px 40px; max-width: 1400px; margin: 0 auto; }
  section { background: #16213e; border-radius: 8px; margin-bottom: 24px; overflow: hidden; border: 1px solid #0f3460; }
  section h2 { background: #0f3460; color: #00d4ff; padding: 14px 20px; font-size: 1em; letter-spacing: 2px; text-transform: uppercase; display: flex; align-items: center; gap: 10px; }
  section .content { padding: 20px; }
  .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .kv { display: flex; gap: 10px; padding: 6px 0; border-bottom: 1px solid #0f3460; }
  .kv:last-child { border-bottom: none; }
  .kv .key   { color: #888; min-width: 140px; font-size: 0.85em; }
  .kv .value { color: #e0e0e0; font-weight: 500; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  th { background: #0f3460; color: #00d4ff; padding: 10px 12px; text-align: left; font-weight: 600; letter-spacing: 1px; text-transform: uppercase; font-size: 0.78em; }
  td { padding: 8px 12px; border-bottom: 1px solid #1e3a5f; color: #ccc; }
  tr:hover td { background: #1e3a5f; }
  .empty { color: #666; padding: 12px 0; font-style: italic; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 0.78em; font-weight: 700; letter-spacing: 1px; text-transform: uppercase; }
  .badge-ok   { background: #1a4a2e; color: #2ecc71; border: 1px solid #2ecc71; }
  .badge-warn { background: #4a3000; color: #f39c12; border: 1px solid #f39c12; }
  .badge-err  { background: #4a0000; color: #e74c3c; border: 1px solid #e74c3c; }
  footer { text-align: center; padding: 20px; color: #444; font-size: 0.8em; border-top: 1px solid #0f3460; }
</style>
</head>
<body>
<header>
  <h1>P.R.O.B.E.</h1>
  <p>Performs Rapid Operating-system Baseline Evaluation</p>
  <div class="meta">
    <span><strong>Machine:</strong> $env:COMPUTERNAME</span>
    <span><strong>Run As:</strong> $env:USERDOMAIN\$env:USERNAME</span>
    <span><strong>Generated:</strong> $ExecutionTime</span>
    <span><strong>Updates:</strong> $updateBadge</span>
    <span><strong>Events (24h):</strong> $eventBadge</span>
  </div>
</header>
<main>

  <!-- HARDWARE -->
  <section>
    <h2>Hardware</h2>
    <div class="content">
      <div class="grid-2">
        <div>
          <div class="kv"><span class="key">Manufacturer</span><span class="value">$($hw.Manufacturer)</span></div>
          <div class="kv"><span class="key">Model</span><span class="value">$($hw.Model)</span></div>
          <div class="kv"><span class="key">Serial Number</span><span class="value">$($hw.Serial)</span></div>
        </div>
        <div>
          <div class="kv"><span class="key">CPU</span><span class="value">$($hw.CPU)</span></div>
          <div class="kv"><span class="key">Cores / Threads</span><span class="value">$($hw.Cores) / $($hw.Threads)</span></div>
          <div class="kv"><span class="key">RAM</span><span class="value">$($hw.RAMGB) GB</span></div>
        </div>
      </div>
      <br>
      <table>
        <thead><tr><th>Drive</th><th>Label</th><th>Total</th><th>Used</th><th>Free</th><th>Usage</th></tr></thead>
        <tbody>$diskRows</tbody>
      </table>
    </div>
  </section>

  <!-- OPERATING SYSTEM -->
  <section>
    <h2>Operating System</h2>
    <div class="content">
      <div class="kv"><span class="key">OS</span><span class="value">$($osRep.Caption)</span></div>
      <div class="kv"><span class="key">Build</span><span class="value">$($osRep.Build)</span></div>
      <div class="kv"><span class="key">Architecture</span><span class="value">$($osRep.Architecture)</span></div>
      <div class="kv"><span class="key">Install Date</span><span class="value">$($osRep.InstallDate)</span></div>
      <div class="kv"><span class="key">Activation</span><span class="value">$($osRep.Activation)</span></div>
    </div>
  </section>

  <!-- NETWORK -->
  <section>
    <h2>Network Configuration</h2>
    <div class="content">
      <table>
        <thead><tr><th>Adapter</th><th>IP Address</th><th>MAC</th><th>Gateway</th><th>DNS</th></tr></thead>
        <tbody>$netRows</tbody>
      </table>
    </div>
  </section>

  <!-- HEALTH -->
  <section>
    <h2>System Health</h2>
    <div class="content">
      <div class="kv"><span class="key">Last Boot</span><span class="value">$($health.LastBoot)</span></div>
      <div class="kv"><span class="key">Uptime</span><span class="value">$($health.Uptime)</span></div>
      <div class="kv"><span class="key">Battery</span><span class="value">$(if ($health.Battery) { "$($health.Battery.Charge)% -- $($health.Battery.Status)" } else { "N/A" })</span></div>
    </div>
  </section>

  <!-- PENDING UPDATES -->
  <section>
    <h2>Pending Windows Updates $updateBadge</h2>
    <div class="content">$updatesTable</div>
  </section>

  <!-- INSTALLED SOFTWARE -->
  <section>
    <h2>Installed Software ($($reportData['Software'].Count) apps)</h2>
    <div class="content">$softwareTable</div>
  </section>

  <!-- EVENT LOG -->
  <section>
    <h2>Event Log -- Errors &amp; Critical (Last 24h) $eventBadge</h2>
    <div class="content">$eventsTable</div>
  </section>

</main>
<footer>
  Generated by P.R.O.B.E. -- Technician Toolkit LiveConnect Suite &nbsp;|&nbsp; $ExecutionTime
</footer>
</body>
</html>
"@

try {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    $htmlReport | Out-File -FilePath $reportFullPath -Encoding UTF8 -Force
    Write-Host "[OK] Report saved: $reportFullPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Could not save report: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ===========================
# SUMMARY
# ===========================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PROBE DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  OS        : $($reportData['OS'].Caption)" -ForegroundColor Gray
Write-Host "  RAM       : $($reportData['Hardware'].RAMGB) GB" -ForegroundColor Gray
Write-Host "  Uptime    : $($reportData['Health'].Uptime)" -ForegroundColor Gray

if ($updateCount -gt 0) {
    Write-Host "  Updates   : $updateCount pending" -ForegroundColor Yellow
} else {
    Write-Host "  Updates   : Up to date" -ForegroundColor Green
}

if ($eventCount -gt 0) {
    Write-Host "  Events    : $eventCount error(s) in last 24h" -ForegroundColor Yellow
} else {
    Write-Host "  Events    : Clean" -ForegroundColor Green
}

Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] P.R.O.B.E. diagnostic complete." -ForegroundColor Cyan
Write-Host ""
