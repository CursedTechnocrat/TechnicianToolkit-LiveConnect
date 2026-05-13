<#
.SYNOPSIS
    T.O.R.C.H. — Test Of Reachable Connected Hosts
    LiveConnect-Compatible Network Discovery & Asset Inventory for PowerShell 5.1+

.DESCRIPTION
    Scans the local /24 subnet to discover live hosts via parallel ping sweep,
    resolves hostnames through DNS reverse lookup, reads MAC addresses from
    the ARP neighbor table, optionally TCP-port-scans common service ports
    (21/22/23/80/443/445/3389/5985/8080/8443), and produces a dark-themed
    HTML inventory report. Also writes a CSV alongside the HTML.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\torch.ps1                       # Sweep + HTML, port scan included by default
    PS C:\> .\torch.ps1 -SkipPortScan         # Sweep only, no TCP port scan
    PS C:\> .\torch.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath     Folder where the HTML + CSV are saved (default: C:\Temp)
    -SkipPortScan   Skip the TCP port scan stage (default: scan ten common ports)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : L.A.N.T.E.R.N. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [switch]$SkipPortScan
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$timestamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportFilename = "TORCH_${timestamp}.html"
$csvFilename    = "TORCH_${timestamp}.csv"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename
$csvFullPath    = Join-Path $ReportPath $csvFilename

Write-Host ""
Write-Host "  T.O.R.C.H. -- Test Of Reachable Connected Hosts" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As     : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time       : $ExecutionTime" -ForegroundColor Gray
Write-Host "  PortScan   : $(if ($SkipPortScan) { 'skipped' } else { 'enabled' })" -ForegroundColor Gray
Write-Host "  Report     : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

$ScanPorts = @(21, 22, 23, 80, 443, 445, 3389, 5985, 8080, 8443)

function Test-TCPPort {
    param([string]$Hostname, [int]$Port, [int]$TimeoutMs = 1500)
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($Hostname, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Get-LocalSubnetPrefix {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notmatch '^127\.' -and
            $_.IPAddress -notmatch '^169\.254\.' -and
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Sort-Object -Property PrefixLength -Descending |
        Select-Object -First 1
    if (-not $ip) { return $null }
    $parts = $ip.IPAddress -split '\.'
    return ($parts[0..2] -join '.')
}

# ===========================
# SUBNET SWEEP
# ===========================

$prefix = Get-LocalSubnetPrefix
if (-not $prefix) {
    Write-Host "[ERROR] Could not determine local IP address. Ensure a network adapter is connected." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Local subnet detected: $prefix.0/24" -ForegroundColor Gray
Write-Host "[*] Sweeping $prefix.1 - $prefix.254 via parallel ping..." -ForegroundColor Magenta

$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 50)
$pool.Open()

$jobs = New-Object 'System.Collections.Generic.List[hashtable]'
$pingScript = {
    param([string]$IP)
    $result = @{ IP = $IP; Alive = $false; ResponseTimeMs = -1 }
    try {
        $ping  = [System.Net.NetworkInformation.Ping]::new()
        $reply = $ping.Send($IP, 1000)
        if ($reply.Status -eq 'Success') {
            $result.Alive = $true
            $result.ResponseTimeMs = [int]$reply.RoundtripTime
        }
    } catch {}
    return $result
}

for ($i = 1; $i -le 254; $i++) {
    $ip = "$prefix.$i"
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($pingScript).AddArgument($ip)
    $handle = $ps.BeginInvoke()
    $jobs.Add(@{ PS = $ps; Handle = $handle })
}

$timeout = (Get-Date).AddSeconds(15)
$completed = 0
$alive = New-Object 'System.Collections.Generic.List[hashtable]'

while ($completed -lt $jobs.Count -and (Get-Date) -lt $timeout) {
    foreach ($job in $jobs) {
        if (-not $job.ContainsKey('Done') -and $job.Handle.IsCompleted) {
            $res = $job.PS.EndInvoke($job.Handle)
            $job.PS.Dispose()
            $job['Done'] = $true
            $completed++
            if ($res -and $res.Alive) { $alive.Add($res) }
        }
    }
    Start-Sleep -Milliseconds 50
}
foreach ($job in $jobs) {
    if (-not $job.ContainsKey('Done')) {
        try { $job.PS.Stop() } catch {}
        $job.PS.Dispose()
    }
}
$pool.Close(); $pool.Dispose()

Write-Host "[OK] Sweep complete. $($alive.Count) responding host(s) found." -ForegroundColor Green
Write-Host ""

if ($alive.Count -eq 0) {
    Write-Host "[!!] No hosts responded. Check network connectivity." -ForegroundColor Yellow
    exit 0
}

# ARP lookup
Write-Host "[*] Reading ARP neighbor table..." -ForegroundColor Magenta
$arpLookup = @{}
Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' } |
    ForEach-Object { $arpLookup[$_.IPAddress] = $_.LinkLayerAddress }

Write-Host "[*] Resolving hostnames..." -ForegroundColor Magenta
$discovered = @()
foreach ($r in ($alive | Sort-Object { [version]$_.IP })) {
    $hostname = ''
    try { $hostname = ([System.Net.Dns]::GetHostEntry($r.IP)).HostName } catch {}
    $mac = if ($arpLookup.ContainsKey($r.IP)) { $arpLookup[$r.IP] } else { '' }
    $discovered += [PSCustomObject]@{
        IP             = $r.IP
        Hostname       = $hostname
        MAC            = $mac
        OpenPorts      = @()
        ResponseTimeMs = $r.ResponseTimeMs
        LastSeen       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}
Write-Host "[OK] Discovery complete. $($discovered.Count) host(s) inventoried." -ForegroundColor Green
Write-Host ""

# ===========================
# PORT SCAN
# ===========================

if (-not $SkipPortScan) {
    $totalOps = $discovered.Count * $ScanPorts.Count
    Write-Host "[*] TCP-port scanning $($discovered.Count) host(s) across $($ScanPorts.Count) ports ($totalOps checks)..." -ForegroundColor Magenta
    Write-Host "    Ports: $($ScanPorts -join ', ')" -ForegroundColor Gray
    foreach ($h in $discovered) {
        $open = @()
        foreach ($p in $ScanPorts) {
            if (Test-TCPPort -Hostname $h.IP -Port $p -TimeoutMs 1500) { $open += $p }
        }
        $h.OpenPorts = $open
        $portDisplay = if ($open.Count -gt 0) { $open -join ', ' } else { 'none' }
        $portColor   = if ($open.Count -gt 0) { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-18} {1}" -f $h.IP, $portDisplay) -ForegroundColor $portColor
    }
    Write-Host "[OK] Port scan complete." -ForegroundColor Green
    Write-Host ""
}

$rdpExposed = ($discovered | Where-Object { $_.OpenPorts -contains 3389 } | Measure-Object).Count
$smbExposed = ($discovered | Where-Object { $_.OpenPorts -contains 445  } | Measure-Object).Count
$tnExposed  = ($discovered | Where-Object { $_.OpenPorts -contains 23   } | Measure-Object).Count

if ($rdpExposed -gt 0) { Write-Host "[!!] RDP exposed (port 3389): $rdpExposed host(s)" -ForegroundColor Yellow }
if ($smbExposed -gt 0) { Write-Host "[!!] SMB exposed (port 445):  $smbExposed host(s)" -ForegroundColor Yellow }
if ($tnExposed  -gt 0) { Write-Host "[!!] Telnet exposed (port 23): $tnExposed host(s)" -ForegroundColor Red }
Write-Host ""

# ===========================
# CSV EXPORT
# ===========================

try {
    $discovered |
        Sort-Object { [version]$_.IP } |
        Select-Object IP, Hostname, MAC,
            @{ N='OpenPorts'; E={ $_.OpenPorts -join ',' } },
            ResponseTimeMs, LastSeen |
        Export-Csv -Path $csvFullPath -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] CSV saved: $csvFullPath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Could not write CSV: $($_.Exception.Message)" -ForegroundColor Red
}

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

function PortBadges([int[]]$Ports) {
    if (-not $Ports -or $Ports.Count -eq 0) { return '<span style="color:#666;">none</span>' }
    $badges = foreach ($p in $Ports) {
        $label = switch ($p) {
            21   { 'FTP' }    22   { 'SSH' }    23   { 'Telnet' }
            80   { 'HTTP' }   443  { 'HTTPS' }  445  { 'SMB' }
            3389 { 'RDP' }    5985 { 'WinRM' }  8080 { 'HTTP-Alt' }
            8443 { 'HTTPS-Alt' } default { "$p" }
        }
        $cls = switch ($p) {
            { $_ -in @(3389, 445, 23) } { 'badge-crit' }
            { $_ -in @(80, 8080) }       { 'badge-warn' }
            { $_ -in @(443, 8443) }      { 'badge-ok' }
            default                      { 'badge-neutral' }
        }
        "<span class='badge $cls'>$label</span>"
    }
    return ($badges -join ' ')
}

$tableRows = ""
foreach ($h in ($discovered | Sort-Object { [version]$_.IP })) {
    $hostname   = if ($h.Hostname) { HtmlEncode $h.Hostname } else { '<span style="color:#555;">-</span>' }
    $mac        = if ($h.MAC)      { HtmlEncode $h.MAC }      else { '<span style="color:#555;">-</span>' }
    $rtt        = if ($h.ResponseTimeMs -ge 0) { "$($h.ResponseTimeMs) ms" } else { '-' }
    $portBadges = PortBadges $h.OpenPorts
    $rowRisk = if ($h.OpenPorts -contains 3389 -or $h.OpenPorts -contains 445 -or $h.OpenPorts -contains 23) {
        "<span class='badge badge-crit'>Risk</span>"
    } elseif ($h.OpenPorts.Count -gt 0) {
        "<span class='badge badge-ok'>Active</span>"
    } else {
        ''
    }
    $tableRows += @"
        <tr>
            <td><strong>$($h.IP)</strong></td>
            <td>$hostname</td>
            <td><code>$mac</code></td>
            <td>$portBadges</td>
            <td>$rtt</td>
            <td>$rowRisk</td>
        </tr>
"@
}

$rdpClass = if ($rdpExposed -gt 0) { 'crit' } else { 'ok' }
$smbClass = if ($smbExposed -gt 0) { 'warn' } else { 'ok' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>T.O.R.C.H. Network Discovery -- $prefix.0/24</title>
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
  code { background: #0f1928; padding: 1px 6px; border-radius: 3px; font-size: 12px; color: #00d4ff; word-break: break-all; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; margin-right: 3px; }
  .badge-ok      { background: #1a4a2e; color: #2ecc71; }
  .badge-warn    { background: #4a3a10; color: #f39c12; }
  .badge-crit    { background: #4a1a1a; color: #e74c3c; }
  .badge-neutral { background: #2a2a3e; color: #aaa; }
  .section-title { color: #00d4ff; font-size: 15px; margin: 28px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
  .note { color: #aaa; font-size: 12px; margin-bottom: 18px; }
</style>
</head>
<body>
<h1>T.O.R.C.H. -- Network Discovery</h1>
<div class="subtitle">Subnet: <strong>$prefix.0/24</strong> &nbsp;|&nbsp; Host: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="note">Port scan covers: 21 (FTP), 22 (SSH), 23 (Telnet), 80 (HTTP), 443 (HTTPS), 445 (SMB), 3389 (RDP), 5985 (WinRM), 8080, 8443. $(if ($SkipPortScan) { '<strong>This run did not include the TCP port scan.</strong>' })</div>

<div class="summary">
  <div class="card"><div class="val">$($discovered.Count)</div><div class="lbl">Total Hosts</div></div>
  <div class="card $rdpClass"><div class="val">$rdpExposed</div><div class="lbl">RDP Exposed (3389)</div></div>
  <div class="card $smbClass"><div class="val">$smbExposed</div><div class="lbl">SMB Exposed (445)</div></div>
  <div class="card $(if ($tnExposed -gt 0) { 'crit' } else { 'ok' })"><div class="val">$tnExposed</div><div class="lbl">Telnet Exposed (23)</div></div>
</div>

<div class="section-title">Host Inventory</div>
<table>
  <thead><tr><th>IP Address</th><th>Hostname</th><th>MAC</th><th>Open Ports</th><th>RTT</th><th>Risk</th></tr></thead>
  <tbody>$tableRows</tbody>
</table>

<div class="footer">
  Generated by T.O.R.C.H. -- Technician Toolkit LiveConnect Suite. CSV saved alongside this report.
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
Write-Host "  CSV PATH   : $csvFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] T.O.R.C.H. complete." -ForegroundColor Cyan
Write-Host ""
