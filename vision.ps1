<#
.SYNOPSIS
    V.I.S.I.O.N. — Verifies Inventory, Status & Operational Numbers
    LiveConnect-Compatible Unified 5-Section Diagnostic Report for PowerShell 5.1+

.DESCRIPTION
    Runs five diagnostic queries in a single pass and produces one
    comprehensive HTML report suitable for machine handoffs or audit records:

      1. System overview (OS, hardware, RAM, uptime)
      2. Local user accounts (admins, last logon, password required)
      3. Disk space (per-volume usage with progress bars)
      4. Disk health (Get-PhysicalDisk + StorageReliabilityCounter — temp, wear)
      5. Services & scheduled tasks (stopped auto-start services, failed tasks)

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\vision.ps1
    PS C:\> .\vision.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : S.C.R.Y.E.R. (main toolkit)
#>

param([string]$ReportPath = "C:\Temp")

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "VISION_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  V.I.S.I.O.N. -- Verifies Inventory, Status & Operational Numbers" -ForegroundColor Cyan
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

# ===========================
# SECTION 1 — SYSTEM OVERVIEW
# ===========================

Write-Host "[1/5] Collecting system information..." -ForegroundColor Magenta
$sysOS  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$sysCS  = Get-CimInstance -ClassName Win32_ComputerSystem  -ErrorAction SilentlyContinue
$sysCPU = Get-CimInstance -ClassName Win32_Processor       -ErrorAction SilentlyContinue | Select-Object -First 1

$osCaption    = if ($sysOS)  { $sysOS.Caption }                                else { "Unknown" }
$osBuild      = if ($sysOS)  { $sysOS.BuildNumber }                            else { "" }
$manufacturer = if ($sysCS)  { $sysCS.Manufacturer }                           else { "" }
$model        = if ($sysCS)  { $sysCS.Model }                                  else { "" }
$cpuName      = if ($sysCPU) { $sysCPU.Name.Trim() }                           else { "Unknown" }
$cpuCores     = if ($sysCS)  { $sysCS.NumberOfLogicalProcessors }              else { "" }
$totalRAM_GB  = if ($sysCS)  { [math]::Round($sysCS.TotalPhysicalMemory / 1GB, 1) } else { 0 }
$freeRAM_GB   = if ($sysOS)  { [math]::Round($sysOS.FreePhysicalMemory / 1MB, 1) }  else { 0 }
$lastBoot     = if ($sysOS)  { $sysOS.LastBootUpTime.ToString("yyyy-MM-dd HH:mm") } else { "" }
$uptimeSpan   = if ($sysOS)  { (Get-Date) - $sysOS.LastBootUpTime }            else { $null }
$uptimeStr    = if ($uptimeSpan) { "$([int]$uptimeSpan.TotalDays)d $($uptimeSpan.Hours)h" } else { "" }
$psVersion    = $PSVersionTable.PSVersion.ToString()
Write-Host "[OK] System info collected." -ForegroundColor Green

# ===========================
# SECTION 2 — USER ACCOUNTS
# ===========================

Write-Host "[2/5] Auditing local user accounts..." -ForegroundColor Magenta
$localUsers = Get-LocalUser -ErrorAction SilentlyContinue
$adminMembers = @()
try { $adminMembers = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue).Name } catch {}

$userRows = foreach ($u in ($localUsers | Sort-Object @{Expression={ -not ($adminMembers -contains "$env:COMPUTERNAME\$($u.Name)") }}, @{Expression={ $_.LastLogon };Descending=$true})) {
    $isAdmin = ($adminMembers -contains "$env:COMPUTERNAME\$($u.Name)") -or ($adminMembers -contains $u.Name)
    [PSCustomObject]@{
        Name        = $u.Name
        FullName    = $u.FullName
        Enabled     = $u.Enabled
        LastLogon   = if ($u.LastLogon) { $u.LastLogon.ToString("yyyy-MM-dd") } else { "Never" }
        IsAdmin     = $isAdmin
        PwdRequired = $u.PasswordRequired
    }
}
Write-Host "[OK] $($userRows.Count) user account(s) audited." -ForegroundColor Green

# ===========================
# SECTION 3 — DISK SPACE
# ===========================

Write-Host "[3/5] Checking disk space..." -ForegroundColor Magenta
$volumes = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
$volumeRows = foreach ($v in $volumes) {
    $totalGB = [math]::Round($v.Size / 1GB, 1)
    $freeGB  = [math]::Round($v.FreeSpace / 1GB, 1)
    $usedGB  = [math]::Round(($v.Size - $v.FreeSpace) / 1GB, 1)
    $pctUsed = if ($v.Size -gt 0) { [math]::Round(($v.Size - $v.FreeSpace) / $v.Size * 100, 0) } else { 0 }
    $health  = if ($pctUsed -gt 95) { 'crit' } elseif ($pctUsed -gt 85) { 'warn' } else { 'ok' }
    [PSCustomObject]@{
        Letter = $v.DeviceID; Label = $v.VolumeName
        TotalGB = $totalGB; UsedGB = $usedGB; FreeGB = $freeGB
        PctUsed = $pctUsed; Health = $health
    }
}
$volWarnCount = ($volumeRows | Where-Object { $_.Health -ne 'ok' } | Measure-Object).Count
Write-Host "[OK] $($volumeRows.Count) volume(s) checked ($volWarnCount with warnings)." -ForegroundColor Green

# ===========================
# SECTION 4 — DISK HEALTH
# ===========================

Write-Host "[4/5] Assessing disk health..." -ForegroundColor Magenta
$diskRows = @()
$smartAvailable = $false
try {
    $physDisks = Get-PhysicalDisk -ErrorAction Stop
    $smartAvailable = $true
    $diskRows = foreach ($d in $physDisks) {
        $sizeGB = [math]::Round($d.Size / 1GB, 0)
        $wear = $null; $temp = $null
        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue
            if ($rel) { $wear = $rel.Wear; $temp = $rel.Temperature }
        } catch {}
        $cls = switch -Regex ($d.HealthStatus) {
            'Healthy' { 'ok' } 'Warning' { 'warn' } default { 'crit' }
        }
        [PSCustomObject]@{
            Name        = "$($d.FriendlyName)"
            MediaType   = "$($d.MediaType)"
            SizeGB      = $sizeGB
            Health      = "$($d.HealthStatus)"
            HealthClass = $cls
            Temp        = $temp
            Wear        = $wear
        }
    }
} catch { $smartAvailable = $false }
$diskWarnCount = ($diskRows | Where-Object { $_.HealthClass -ne 'ok' } | Measure-Object).Count
Write-Host "[OK] $($diskRows.Count) disk(s) assessed." -ForegroundColor Green

# ===========================
# SECTION 5 — SERVICES & TASKS
# ===========================

Write-Host "[5/5] Checking services and scheduled tasks..." -ForegroundColor Magenta
$triggerExclusions = @('gupdate','gupdatem','edgeupdate','edgeupdatem','MapsBroker',
    'RemoteRegistry','SharedAccess','TabletInputService','WbioSrvc','lfsvc',
    'SCardSvr','SensrSvc','WSearch','wuauserv','BITS','DoSvc','UsoSvc','WerSvc',
    'AppReadiness','tiledatamodelsvc','CDPSvc','OneSyncSvc','PimIndexMaintenanceSvc',
    'MessagingService','cbdhsvc','DevicesFlowUserSvc')

$stoppedSvcs = @(Get-Service -ErrorAction SilentlyContinue |
    Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -eq 'Stopped' -and $_.Name -notin $triggerExclusions } |
    Select-Object Name, DisplayName, Status, StartType |
    Sort-Object DisplayName)

$failedTasks = @()
try {
    $failedTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' } |
        ForEach-Object {
            $info = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
            if ($info -and $info.LastTaskResult -ne 0 -and $info.LastRunTime -gt [datetime]::MinValue) {
                [PSCustomObject]@{
                    TaskName    = $_.TaskName
                    TaskPath    = $_.TaskPath
                    LastRunTime = $info.LastRunTime.ToString("yyyy-MM-dd HH:mm")
                    LastResult  = "0x{0:X8}" -f $info.LastTaskResult
                }
            }
        } | Where-Object { $_ -ne $null } | Select-Object -First 20)
} catch {}
Write-Host "[OK] $($stoppedSvcs.Count) stopped svc(s), $($failedTasks.Count) failed task(s)." -ForegroundColor Green
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$userTableRows = ""
foreach ($u in $userRows) {
    $statusBadge = if ($u.Enabled) { "<span class='badge badge-ok'>Enabled</span>" } else { "<span class='badge badge-crit'>Disabled</span>" }
    $adminCell   = if ($u.IsAdmin) { "<span class='badge badge-crit'>Yes</span>" } else { "" }
    $pwdCell     = if ($u.PwdRequired) { 'Yes' } else { 'No' }
    $userTableRows += "<tr><td><strong>$(HtmlEncode $u.Name)</strong></td><td>$(HtmlEncode $u.FullName)</td><td>$statusBadge</td><td>$(HtmlEncode $u.LastLogon)</td><td>$adminCell</td><td>$pwdCell</td></tr>"
}

$diskSpaceCards = ""
foreach ($vol in $volumeRows) {
    $letterLabel = if ($vol.Label) { "$(HtmlEncode $vol.Letter) -- $(HtmlEncode $vol.Label)" } else { HtmlEncode $vol.Letter }
    $barColor    = switch ($vol.Health) { 'crit' { '#e74c3c' } 'warn' { '#f39c12' } default { '#2ecc71' } }
    $diskSpaceCards += @"
    <div class="vol">
      <div class="vol-head">$letterLabel</div>
      <div class="bar-wrap"><div class="bar" style="width:$($vol.PctUsed)%;background:$barColor;"></div></div>
      <div class="vol-meta">$($vol.PctUsed)% used &nbsp;|&nbsp; $($vol.UsedGB) GB used / $($vol.TotalGB) GB total &nbsp;|&nbsp; $($vol.FreeGB) GB free</div>
    </div>
"@
}
if (-not $diskSpaceCards) { $diskSpaceCards = "<div style='color:#aaa;'>No fixed volumes found.</div>" }

if (-not $smartAvailable) {
    $diskHealthBody = "<div style='color:#aaa;'>SMART data unavailable -- Storage module not accessible on this system.</div>"
} else {
    $diskHealthRows = ""
    foreach ($d in $diskRows) {
        $hb = "<span class='badge badge-$($d.HealthClass)'>$(HtmlEncode $d.Health)</span>"
        $temp = if ($null -ne $d.Temp) { "$($d.Temp)" } else { '--' }
        $wear = if ($null -ne $d.Wear) { "$($d.Wear)%" } else { '--' }
        $diskHealthRows += "<tr><td>$(HtmlEncode $d.Name)</td><td>$(HtmlEncode $d.MediaType)</td><td>$($d.SizeGB)</td><td>$hb</td><td>$temp</td><td>$wear</td></tr>"
    }
    $diskHealthBody = @"
<table>
  <thead><tr><th>Drive</th><th>Type</th><th>Size (GB)</th><th>Health</th><th>Temp</th><th>Wear</th></tr></thead>
  <tbody>$diskHealthRows</tbody>
</table>
"@
}

$svcCardBody = ""
if ($stoppedSvcs.Count -eq 0) {
    $svcCardBody = "<div class='badge badge-ok' style='display:inline-block;padding:8px 12px;'>OK -- No stopped automatic services found.</div>"
} else {
    $svcRows = ""
    foreach ($s in $stoppedSvcs) {
        $svcRows += "<tr><td><code>$(HtmlEncode $s.Name)</code></td><td>$(HtmlEncode $s.DisplayName)</td><td><span class='badge badge-warn'>Stopped</span></td><td>$(HtmlEncode "$($s.StartType)")</td></tr>"
    }
    $svcCardBody = @"
<table>
  <thead><tr><th>Name</th><th>Display Name</th><th>Status</th><th>Start Type</th></tr></thead>
  <tbody>$svcRows</tbody>
</table>
"@
}

$taskCardBody = ""
if ($failedTasks.Count -eq 0) {
    $taskCardBody = "<div class='badge badge-ok' style='display:inline-block;padding:8px 12px;'>OK -- No failed scheduled tasks found.</div>"
} else {
    $taskRowsHtml = ""
    foreach ($t in $failedTasks) {
        $taskRowsHtml += "<tr><td>$(HtmlEncode $t.TaskName)</td><td><code>$(HtmlEncode $t.TaskPath)</code></td><td>$(HtmlEncode $t.LastRunTime)</td><td><span class='badge badge-warn'>$(HtmlEncode $t.LastResult)</span></td></tr>"
    }
    $taskCardBody = @"
<table>
  <thead><tr><th>Task Name</th><th>Path</th><th>Last Run</th><th>Last Result</th></tr></thead>
  <tbody>$taskRowsHtml</tbody>
</table>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>V.I.S.I.O.N. Unified Diagnostic -- $env:COMPUTERNAME</title>
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
  td { padding: 9px 12px; border-bottom: 1px solid #1e2d4d; vertical-align: top; }
  tr:hover td { background: #1e2d4d; }
  code { background: #0f1928; padding: 1px 6px; border-radius: 3px; font-size: 12px; color: #00d4ff; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; }
  .badge-ok      { background: #1a4a2e; color: #2ecc71; }
  .badge-warn    { background: #4a3a10; color: #f39c12; }
  .badge-crit    { background: #4a1a1a; color: #e74c3c; }
  .badge-neutral { background: #2a2a3e; color: #aaa; }
  .section-title { color: #00d4ff; font-size: 16px; margin: 32px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  .section-num { color: #888; font-size: 12px; margin-right: 8px; }
  .vol { background: #16213e; padding: 12px 16px; border-radius: 6px; margin: 8px 0; }
  .vol-head { color: #00d4ff; font-size: 13px; margin-bottom: 6px; }
  .vol-meta { color: #aaa; font-size: 12px; margin-top: 4px; }
  .bar-wrap { background: #0f1928; height: 14px; border-radius: 4px; overflow: hidden; }
  .bar { height: 14px; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>V.I.S.I.O.N. -- Unified Diagnostic Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; OS: $(HtmlEncode $osCaption) (Build $osBuild)</div>

<div class="summary">
  <div class="card"><div class="val">$($userRows.Count)</div><div class="lbl">User Accounts</div></div>
  <div class="card $(if ($volWarnCount -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($volumeRows.Count)</div><div class="lbl">Volumes ($volWarnCount warn)</div></div>
  <div class="card $(if ($diskWarnCount -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($diskRows.Count)</div><div class="lbl">Physical Disks</div></div>
  <div class="card $(if ($stoppedSvcs.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($stoppedSvcs.Count)</div><div class="lbl">Stopped Svc</div></div>
  <div class="card $(if ($failedTasks.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($failedTasks.Count)</div><div class="lbl">Failed Tasks</div></div>
  <div class="card"><div class="val">$uptimeStr</div><div class="lbl">Uptime</div></div>
</div>

<div class="section-title"><span class="section-num">01</span>System Overview</div>
<table>
  <tbody>
    <tr><th>Hostname</th><td>$(HtmlEncode $env:COMPUTERNAME)</td></tr>
    <tr><th>Operating System</th><td>$(HtmlEncode $osCaption) (Build $osBuild)</td></tr>
    <tr><th>Manufacturer / Model</th><td>$(HtmlEncode $manufacturer) $(HtmlEncode $model)</td></tr>
    <tr><th>CPU</th><td>$(HtmlEncode $cpuName) ($cpuCores logical cores)</td></tr>
    <tr><th>RAM</th><td>$totalRAM_GB GB total / $freeRAM_GB GB free</td></tr>
    <tr><th>Last Boot</th><td>$(HtmlEncode $lastBoot)</td></tr>
    <tr><th>Uptime</th><td>$(HtmlEncode $uptimeStr)</td></tr>
    <tr><th>PowerShell Version</th><td>$(HtmlEncode $psVersion)</td></tr>
  </tbody>
</table>

<div class="section-title"><span class="section-num">02</span>User Accounts</div>
<table>
  <thead><tr><th>User</th><th>Full Name</th><th>Status</th><th>Last Logon</th><th>Admin</th><th>Pwd Required</th></tr></thead>
  <tbody>$userTableRows</tbody>
</table>

<div class="section-title"><span class="section-num">03</span>Disk Space</div>
$diskSpaceCards

<div class="section-title"><span class="section-num">04</span>Disk Health</div>
$diskHealthBody

<div class="section-title"><span class="section-num">05</span>Services &amp; Scheduled Tasks</div>
<div style="margin-bottom:18px;"><div style="color:#888;font-size:12px;text-transform:uppercase;margin-bottom:6px;">Stopped Automatic Services</div>$svcCardBody</div>
<div><div style="color:#888;font-size:12px;text-transform:uppercase;margin-bottom:6px;">Failed Scheduled Tasks</div>$taskCardBody</div>

<div class="footer">
  Generated by V.I.S.I.O.N. -- Technician Toolkit LiveConnect Suite. One-shot 5-section snapshot.
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
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  V.I.S.I.O.N. SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Users      : $($userRows.Count)" -ForegroundColor Gray
Write-Host "  Volumes    : $($volumeRows.Count) ($volWarnCount with warnings)" -ForegroundColor $(if ($volWarnCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Disks      : $($diskRows.Count) ($diskWarnCount with issues)"   -ForegroundColor $(if ($diskWarnCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Svc Issues : $($stoppedSvcs.Count)" -ForegroundColor $(if ($stoppedSvcs.Count -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Task Fails : $($failedTasks.Count)" -ForegroundColor $(if ($failedTasks.Count -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] V.I.S.I.O.N. complete." -ForegroundColor Cyan
Write-Host ""
