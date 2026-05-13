<#
.SYNOPSIS
    S.E.N.T.R.Y. — Services, Events 'N Tasks Reporting Yield
    LiveConnect-Compatible Service / Task / Event Log Monitor for PowerShell 5.1+

.DESCRIPTION
    Read-only audit of 15 critical Windows services (Running / Stopped / Start
    Type), all scheduled tasks (flags non-Microsoft failed / disabled / stale
    entries), and System + Application event-log errors from the last N hours.
    Saves a dark-themed HTML report.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.
    Does NOT restart services automatically; restart actions are out of scope
    for an audit tool. To restart a stopped service, use the host's service
    management UI or a separate scripted action.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\sentry.ps1
    PS C:\> .\sentry.ps1 -ReportPath "C:\Temp"
    PS C:\> .\sentry.ps1 -EventHours 48

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)
    -EventHours   Look-back window for System/Application errors (default: 24, max: 168)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : G.A.R.G.O.Y.L.E. (main toolkit, local-only audit subset)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [ValidateRange(1, 168)] [int]$EventHours = 24
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "SENTRY_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  S.E.N.T.R.Y. -- Services, Events 'N Tasks Reporting Yield" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine     : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As      : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time        : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Event hours : $EventHours" -ForegroundColor Gray
Write-Host "  Report      : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

# ===========================
# CRITICAL SERVICES
# ===========================

$CriticalServices = @(
    @{ Name='wuauserv';          Display='Windows Update' }
    @{ Name='WinDefend';         Display='Windows Defender Antivirus' }
    @{ Name='EventLog';          Display='Windows Event Log' }
    @{ Name='Schedule';          Display='Task Scheduler' }
    @{ Name='Dnscache';          Display='DNS Client' }
    @{ Name='LanmanWorkstation'; Display='Workstation (SMB Client)' }
    @{ Name='W32Time';           Display='Windows Time' }
    @{ Name='SamSs';             Display='Security Accounts Manager' }
    @{ Name='RpcSs';             Display='Remote Procedure Call' }
    @{ Name='BITS';              Display='Background Intelligent Transfer' }
    @{ Name='cryptsvc';          Display='Cryptographic Services' }
    @{ Name='MpsSvc';            Display='Windows Firewall' }
    @{ Name='Spooler';           Display='Print Spooler' }
    @{ Name='lmhosts';           Display='TCP/IP NetBIOS Helper' }
    @{ Name='WerSvc';            Display='Windows Error Reporting' }
)

function Get-ServiceHealth {
    $rows = @()
    foreach ($svc in $CriticalServices) {
        try {
            $s = Get-Service -Name $svc.Name -ErrorAction Stop
            $status    = "$($s.Status)"
            $startType = "$($s.StartType)"
        } catch {
            $status = 'NotFound'; $startType = 'Unknown'
        }
        $concern = ($status -eq 'Stopped' -and $startType -eq 'Automatic')
        $rows += [PSCustomObject]@{
            Name = $svc.Name; DisplayName = $svc.Display
            Status = $status; StartType = $startType; Concern = $concern
        }
    }
    return $rows
}

# ===========================
# SCHEDULED TASKS
# ===========================

function Get-TaskAudit {
    try { $tasks = Get-ScheduledTask -ErrorAction Stop } catch { return @() }

    $cutoff = (Get-Date).AddDays(-7)
    $successCodes = @(0, 267009, 267011)
    $rows = @()
    foreach ($task in $tasks) {
        try { $info = $task | Get-ScheduledTaskInfo -ErrorAction Stop }
        catch { $info = [PSCustomObject]@{ LastRunTime = $null; LastTaskResult = -1; NextRunTime = $null } }

        $isMicrosoft  = $task.TaskPath -like '\Microsoft\*'
        $lastRunStale = ($null -ne $info.LastRunTime -and $info.LastRunTime -lt $cutoff -and $info.LastRunTime -gt [datetime]'1900-01-01')
        $hasFailed    = ($info.LastTaskResult -notin $successCodes)
        $isDisabled   = ($task.State -eq 'Disabled')

        $flagReason = ''
        if ($hasFailed -and $lastRunStale -and -not $isMicrosoft) { $flagReason = 'Failed+Stale' }
        elseif ($hasFailed -and -not $isMicrosoft)                { $flagReason = 'Failed' }
        elseif ($isDisabled -and -not $isMicrosoft)               { $flagReason = 'Disabled' }
        elseif ($hasFailed -and $isMicrosoft)                     { $flagReason = 'MSFailed' }

        $rows += [PSCustomObject]@{
            TaskName       = $task.TaskName
            TaskPath       = $task.TaskPath
            State          = "$($task.State)"
            LastRunTime    = $info.LastRunTime
            LastTaskResult = $info.LastTaskResult
            NextRunTime    = $info.NextRunTime
            IsMicrosoft    = $isMicrosoft
            FlagReason     = $flagReason
        }
    }
    return $rows
}

# ===========================
# EVENT LOG ERRORS
# ===========================

function Get-EventErrors {
    param([int]$Hours)
    $since = (Get-Date).AddHours(-$Hours)

    $sysErrors = @()
    $appErrors = @()
    try { $sysErrors = @(Get-EventLog -LogName System      -EntryType Error -After $since -Newest 50 -ErrorAction Stop) } catch {}
    try { $appErrors = @(Get-EventLog -LogName Application -EntryType Error -After $since -Newest 50 -ErrorAction Stop) } catch {}

    $allErrors = @()
    foreach ($e in $sysErrors) {
        $msg = if ($e.Message -and $e.Message.Length -gt 200) { $e.Message.Substring(0,200) + '...' } else { "$($e.Message)" }
        $allErrors += [PSCustomObject]@{
            Log = 'System'; TimeGenerated = $e.TimeGenerated; EntryType = "$($e.EntryType)"
            Source = $e.Source; EventID = $e.EventID; Message = ($msg -split "`r?`n")[0]
        }
    }
    foreach ($e in $appErrors) {
        $msg = if ($e.Message -and $e.Message.Length -gt 200) { $e.Message.Substring(0,200) + '...' } else { "$($e.Message)" }
        $allErrors += [PSCustomObject]@{
            Log = 'Application'; TimeGenerated = $e.TimeGenerated; EntryType = "$($e.EntryType)"
            Source = $e.Source; EventID = $e.EventID; Message = ($msg -split "`r?`n")[0]
        }
    }

    $sourceSummary = $allErrors | Group-Object Source | Sort-Object Count -Descending |
        Select-Object -First 10 | ForEach-Object { [PSCustomObject]@{ Source = $_.Name; Count = $_.Count } }

    return [PSCustomObject]@{
        Events        = ($allErrors | Sort-Object TimeGenerated -Descending)
        SourceSummary = @($sourceSummary)
        TotalCount    = $allErrors.Count
    }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Checking critical services..." -ForegroundColor Magenta
$services = Get-ServiceHealth
foreach ($svc in $services) {
    $color = switch ($svc.Status) { 'Running' { 'Green' } 'Stopped' { 'Red' } default { 'Yellow' } }
    $tag   = if ($svc.Concern) { '  !! CONCERN' } else { '' }
    Write-Host ("  {0,-22} {1,-34} {2,-12} {3,-10}{4}" -f $svc.Name, $svc.DisplayName, $svc.Status, $svc.StartType, $tag) -ForegroundColor $color
}
$svcOk      = ($services | Where-Object { -not $_.Concern }).Count
$svcConcern = ($services | Where-Object {    $_.Concern }).Count
Write-Host ""
Write-Host ("  Services OK: $svcOk   Concerns: $svcConcern") -ForegroundColor $(if ($svcConcern -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ""

Write-Host "[*] Auditing scheduled tasks..." -ForegroundColor Magenta
$tasks = Get-TaskAudit
$flaggedTasks   = $tasks | Where-Object { $_.FlagReason -and $_.FlagReason -ne 'MSFailed' }
$msFailedTasks  = $tasks | Where-Object { $_.FlagReason -eq 'MSFailed' }
Write-Host ("  Total tasks                  : $($tasks.Count)") -ForegroundColor Gray
Write-Host ("  Flagged non-Microsoft tasks  : $($flaggedTasks.Count)") -ForegroundColor $(if ($flaggedTasks.Count -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("  Microsoft tasks with errors  : $($msFailedTasks.Count)") -ForegroundColor Gray
foreach ($t in $flaggedTasks) {
    Write-Host ("    [{0}] {1}{2} -- state: {3}  result: {4}" -f $t.FlagReason, $t.TaskPath, $t.TaskName, $t.State, $t.LastTaskResult) -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[*] Reading event logs (last $EventHours hours)..." -ForegroundColor Magenta
$events = Get-EventErrors -Hours $EventHours
Write-Host ("  Total errors                 : $($events.TotalCount)") -ForegroundColor $(if ($events.TotalCount -gt 0) { 'Yellow' } else { 'Green' })
if ($events.SourceSummary.Count -gt 0) {
    Write-Host "  Top sources:" -ForegroundColor Gray
    foreach ($s in $events.SourceSummary) {
        $color = if ($s.Count -ge 10) { 'Red' } elseif ($s.Count -ge 3) { 'Yellow' } else { 'Gray' }
        Write-Host ("    {0,-40} {1}" -f $s.Source, $s.Count) -ForegroundColor $color
    }
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$svcRows = ""
foreach ($svc in $services) {
    $statusBadge = if ($svc.Status -eq 'Running') { "<span class='badge badge-ok'>Running</span>" }
                   elseif ($svc.Status -eq 'Stopped') { "<span class='badge badge-crit'>Stopped</span>" }
                   else { "<span class='badge badge-warn'>$(HtmlEncode $svc.Status)</span>" }
    $concernCell = if ($svc.Concern) { "<span class='badge badge-crit'>!! Concern</span>" } else { "<span style='color:#555;'>-</span>" }
    $svcRows += @"
        <tr>
            <td><code>$(HtmlEncode $svc.Name)</code></td>
            <td>$(HtmlEncode $svc.DisplayName)</td>
            <td>$statusBadge</td>
            <td>$(HtmlEncode $svc.StartType)</td>
            <td>$concernCell</td>
        </tr>
"@
}

$taskFlagRows = ""
if ($flaggedTasks.Count -eq 0) {
    $taskFlagRows = "<tr><td colspan='5' style='text-align:center;color:#2ecc71;'>No flagged non-Microsoft tasks.</td></tr>"
} else {
    foreach ($t in ($flaggedTasks | Sort-Object FlagReason)) {
        $flagBadge = switch -Wildcard ($t.FlagReason) {
            'Failed*'  { "<span class='badge badge-crit'>$(HtmlEncode $t.FlagReason)</span>" }
            'Disabled' { "<span class='badge badge-warn'>Disabled</span>" }
            default    { "<span class='badge badge-neutral'>$(HtmlEncode $t.FlagReason)</span>" }
        }
        $lastRun = if ($t.LastRunTime) { $t.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
        $taskFlagRows += "<tr><td><strong>$(HtmlEncode $t.TaskName)</strong></td><td><code>$(HtmlEncode $t.TaskPath)</code></td><td>$(HtmlEncode $t.State)</td><td><code>$($t.LastTaskResult)</code></td><td>$flagBadge</td></tr>"
    }
}

$msFailedRows = ""
if ($msFailedTasks.Count -eq 0) {
    $msFailedRows = "<tr><td colspan='4' style='text-align:center;color:#888;'>No Microsoft task errors.</td></tr>"
} else {
    foreach ($t in ($msFailedTasks | Select-Object -First 20)) {
        $lastRun = if ($t.LastRunTime) { $t.LastRunTime.ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
        $msFailedRows += "<tr><td><strong>$(HtmlEncode $t.TaskName)</strong></td><td><code>$(HtmlEncode $t.TaskPath)</code></td><td>$lastRun</td><td><code>$($t.LastTaskResult)</code></td></tr>"
    }
}

$sourceRows = ""
if ($events.SourceSummary.Count -eq 0) {
    $sourceRows = "<tr><td colspan='2' style='text-align:center;color:#2ecc71;'>No error sources.</td></tr>"
} else {
    foreach ($s in $events.SourceSummary) {
        $bClass = if ($s.Count -ge 10) { 'badge-crit' } elseif ($s.Count -ge 3) { 'badge-warn' } else { 'badge-neutral' }
        $sourceRows += "<tr><td>$(HtmlEncode $s.Source)</td><td><span class='badge $bClass'>$($s.Count)</span></td></tr>"
    }
}

$eventRows = ""
if ($events.TotalCount -eq 0) {
    $eventRows = "<tr><td colspan='5' style='text-align:center;color:#2ecc71;'>No errors in System or Application logs in the last $EventHours hours.</td></tr>"
} else {
    foreach ($e in ($events.Events | Select-Object -First 100)) {
        $logBadge = if ($e.Log -eq 'System') { "<span class='badge badge-neutral'>SYS</span>" } else { "<span class='badge badge-neutral'>APP</span>" }
        $eventRows += "<tr><td>$(HtmlEncode $e.TimeGenerated.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$logBadge</td><td>$(HtmlEncode $e.Source)</td><td><code>$($e.EventID)</code></td><td>$(HtmlEncode $e.Message)</td></tr>"
    }
}

$concernClass = if ($svcConcern -gt 0) { 'crit' } else { 'ok' }
$flagClass    = if ($flaggedTasks.Count -gt 0) { 'warn' } else { 'ok' }
$evClass      = if ($events.TotalCount -ge 10) { 'crit' } elseif ($events.TotalCount -gt 0) { 'warn' } else { 'ok' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>S.E.N.T.R.Y. Services/Tasks/Events -- $env:COMPUTERNAME</title>
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
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>S.E.N.T.R.Y. -- Services / Tasks / Events Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Event window: $EventHours hours</div>

<div class="summary">
  <div class="card ok"><div class="val">$svcOk</div><div class="lbl">Services OK</div></div>
  <div class="card $concernClass"><div class="val">$svcConcern</div><div class="lbl">Service Concerns</div></div>
  <div class="card"><div class="val">$($tasks.Count)</div><div class="lbl">Total Tasks</div></div>
  <div class="card $flagClass"><div class="val">$($flaggedTasks.Count)</div><div class="lbl">Flagged Tasks (non-MS)</div></div>
  <div class="card $evClass"><div class="val">$($events.TotalCount)</div><div class="lbl">Errors (last $EventHours h)</div></div>
</div>

<div class="section-title">Critical Services</div>
<table>
  <thead><tr><th>Service</th><th>Description</th><th>Status</th><th>Start Type</th><th>Concern</th></tr></thead>
  <tbody>$svcRows</tbody>
</table>

<div class="section-title">Flagged Non-Microsoft Scheduled Tasks</div>
<table>
  <thead><tr><th>Task</th><th>Path</th><th>State</th><th>Last Result</th><th>Flag</th></tr></thead>
  <tbody>$taskFlagRows</tbody>
</table>

<div class="section-title">Microsoft Task Errors (up to 20)</div>
<table>
  <thead><tr><th>Task</th><th>Path</th><th>Last Run</th><th>Last Result</th></tr></thead>
  <tbody>$msFailedRows</tbody>
</table>

<div class="section-title">Top Event Sources (last $EventHours hours)</div>
<table>
  <thead><tr><th>Source</th><th>Count</th></tr></thead>
  <tbody>$sourceRows</tbody>
</table>

<div class="section-title">Recent Event-Log Errors (up to 100 newest)</div>
<table>
  <thead><tr><th>Time</th><th>Log</th><th>Source</th><th>Event ID</th><th>Message</th></tr></thead>
  <tbody>$eventRows</tbody>
</table>

<div class="footer">
  Generated by S.E.N.T.R.Y. -- Technician Toolkit LiveConnect Suite. Audit-only; service restart actions are out of scope.
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
Write-Host "[OK] S.E.N.T.R.Y. complete." -ForegroundColor Cyan
Write-Host ""
