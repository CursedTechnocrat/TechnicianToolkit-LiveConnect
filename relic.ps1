# relic.ps1 - R.E.L.I.C. — Reports Expiry of Local Identity Certificates
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
    R.E.L.I.C. — Reports Expiry of Local Identity Certificates
    LiveConnect-Compatible Certificate Health & SSL/TLS Expiry Monitor for PowerShell 5.1+

.DESCRIPTION
    Audits the local Windows certificate stores (Personal, CA, Root,
    TrustedPublisher) for expired and expiring-soon certificates. Optionally
    checks SSL/TLS certificate expiry on remote hosts by connecting and
    reading the presented certificate. Exports a dark-themed HTML report
    with color-coded expiry indicators.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\relic.ps1
    PS C:\> .\relic.ps1 -ReportPath "C:\Temp"
    PS C:\> .\relic.ps1 -Targets "srv1.contoso.com,srv2.contoso.com:8443"
    PS C:\> .\relic.ps1 -Targets "C:\Temp\hosts.txt"   # one host[:port] per line

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)
    -Targets      Optional comma-separated hostnames (hostname or hostname:port),
                  or a path to a text file with one entry per line. Default: none.

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : A.R.T.I.F.A.C.T. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [string]$Targets    = ""
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "RELIC_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  R.E.L.I.C. -- Reports Expiry of Local Identity Certificates" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As    : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time      : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Targets   : $(if ($Targets) { $Targets } else { '(local only)' })" -ForegroundColor Gray
Write-Host "  Report    : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

# ===========================
# COLLECTORS
# ===========================

function Get-LocalCertHealth {
    param([string[]]$StoreNames = @('My','CA','Root','TrustedPublisher'))
    $results = @()
    foreach ($storeName in $StoreNames) {
        try {
            $store = [Security.Cryptography.X509Certificates.X509Store]::new($storeName, 'LocalMachine')
            $store.Open('ReadOnly')
            foreach ($cert in $store.Certificates) {
                $daysLeft = [int]($cert.NotAfter - (Get-Date)).TotalDays
                $status = if     ($daysLeft -lt 0)  { 'Expired' }
                          elseif ($daysLeft -le 30) { 'Critical' }
                          elseif ($daysLeft -le 90) { 'Warning' }
                          else                      { 'Healthy' }
                $results += [PSCustomObject]@{
                    Store      = $storeName
                    Subject    = $cert.Subject
                    Issuer     = $cert.Issuer
                    Thumbprint = $cert.Thumbprint
                    Expiry     = $cert.NotAfter
                    DaysLeft   = $daysLeft
                    Status     = $status
                }
            }
            $store.Close()
        } catch {}
    }
    return $results
}

function Get-SslCertExpiry {
    param([string]$Hostname, [int]$Port = 443, [int]$TimeoutMs = 6000)
    $result = [PSCustomObject]@{
        Hostname = $Hostname; Port = $Port
        Subject  = 'N/A';     Issuer = 'N/A'
        Expiry   = $null;     DaysLeft = $null
        Status   = 'Unknown'; Error = $null
    }
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($Hostname, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $wait) { throw "Connection timed out" }
        $tcp.EndConnect($connect)
        $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($Hostname)
        $cert  = $ssl.RemoteCertificate
        $cert2 = New-Object Security.Cryptography.X509Certificates.X509Certificate2($cert)
        $result.Subject  = $cert2.Subject
        $result.Issuer   = $cert2.Issuer
        $result.Expiry   = $cert2.NotAfter
        $result.DaysLeft = [int]($cert2.NotAfter - (Get-Date)).TotalDays
        $result.Status   = if     ($result.DaysLeft -lt 0)  { 'Expired' }
                           elseif ($result.DaysLeft -le 30) { 'Critical' }
                           elseif ($result.DaysLeft -le 90) { 'Warning' }
                           else                              { 'Healthy' }
        try { $ssl.Dispose() } catch {}
        try { $tcp.Dispose() } catch {}
    } catch {
        $result.Status = 'Error'; $result.Error = $_.Exception.Message
    }
    return $result
}

function ConvertTo-TargetList([string]$TargetString) {
    $entries = @()
    if ([string]::IsNullOrWhiteSpace($TargetString)) { return $entries }
    if (Test-Path $TargetString -PathType Leaf) {
        $lines = Get-Content $TargetString -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('#') }
    } else {
        $lines = $TargetString -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    foreach ($line in $lines) {
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(.+):(\d+)$') {
            $entries += [PSCustomObject]@{ Hostname = $Matches[1].Trim(); Port = [int]$Matches[2] }
        } else {
            $entries += [PSCustomObject]@{ Hostname = $line;              Port = 443 }
        }
    }
    return $entries
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Auditing local certificate stores (My, CA, Root, TrustedPublisher)..." -ForegroundColor Magenta
$localCerts = Get-LocalCertHealth
$expiredCount = ($localCerts | Where-Object { $_.Status -eq 'Expired'  } | Measure-Object).Count
$critCount    = ($localCerts | Where-Object { $_.Status -eq 'Critical' } | Measure-Object).Count
$warnCount    = ($localCerts | Where-Object { $_.Status -eq 'Warning'  } | Measure-Object).Count
$healthyCount = ($localCerts | Where-Object { $_.Status -eq 'Healthy'  } | Measure-Object).Count
Write-Host ("[OK] Total {0}  Expired {1}  Critical {2}  Warning {3}  Healthy {4}" -f $localCerts.Count, $expiredCount, $critCount, $warnCount, $healthyCount) -ForegroundColor Green

$nonHealthy = @($localCerts | Where-Object { $_.Status -ne 'Healthy' } | Sort-Object DaysLeft)
foreach ($c in $nonHealthy) {
    $color = switch ($c.Status) { 'Expired' { 'Red' } 'Critical' { 'Red' } 'Warning' { 'Yellow' } default { 'Gray' } }
    $subj = if ($c.Subject.Length -gt 60) { $c.Subject.Substring(0,57) + '...' } else { $c.Subject }
    Write-Host ("  [{0}] {1,-10} {2,-60} days={3}" -f $c.Status, $c.Store, $subj, $c.DaysLeft) -ForegroundColor $color
}
Write-Host ""

$sslResults = @()
if (-not [string]::IsNullOrWhiteSpace($Targets)) {
    $targetList = ConvertTo-TargetList $Targets
    if ($targetList.Count -gt 0) {
        Write-Host "[*] Checking SSL/TLS certificates on $($targetList.Count) remote host(s)..." -ForegroundColor Magenta
        foreach ($t in $targetList) {
            Write-Host "  [*] $($t.Hostname):$($t.Port)..." -ForegroundColor Magenta
            $r = Get-SslCertExpiry -Hostname $t.Hostname -Port $t.Port
            $sslResults += $r
            $color = switch ($r.Status) { 'Healthy' { 'Green' } 'Warning' { 'Yellow' } 'Critical' { 'Red' } 'Expired' { 'Red' } 'Error' { 'Red' } default { 'Gray' } }
            if ($r.Status -eq 'Error') {
                Write-Host ("    [ERROR] {0}" -f $r.Error) -ForegroundColor Red
            } else {
                Write-Host ("    [{0}] expires {1} ({2} days)" -f $r.Status, $r.Expiry.ToString('yyyy-MM-dd HH:mm'), $r.DaysLeft) -ForegroundColor $color
            }
        }
    }
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$localRows = ""
foreach ($cert in ($localCerts | Sort-Object DaysLeft)) {
    $badge = switch ($cert.Status) {
        'Expired'  { 'badge-crit' }
        'Critical' { 'badge-crit' }
        'Warning'  { 'badge-warn' }
        default    { 'badge-ok' }
    }
    $localRows += "<tr><td><code>$(HtmlEncode $cert.Store)</code></td><td><code>$(HtmlEncode $cert.Subject)</code></td><td><code>$(HtmlEncode $cert.Issuer)</code></td><td>$($cert.Expiry.ToString('yyyy-MM-dd HH:mm'))</td><td>$($cert.DaysLeft)</td><td><span class='badge $badge'>$(HtmlEncode $cert.Status)</span></td></tr>"
}

$sslSection = ""
if ($sslResults.Count -gt 0) {
    $sslRows = ""
    foreach ($r in $sslResults) {
        $badge = switch ($r.Status) {
            'Expired'  { 'badge-crit' }
            'Critical' { 'badge-crit' }
            'Warning'  { 'badge-warn' }
            'Error'    { 'badge-crit' }
            'Healthy'  { 'badge-ok' }
            default    { 'badge-neutral' }
        }
        if ($r.Status -eq 'Error') {
            $sslRows += "<tr><td><strong>$(HtmlEncode $r.Hostname)</strong>:$($r.Port)</td><td><code>$(HtmlEncode $r.Error)</code></td><td>N/A</td><td>N/A</td><td><span class='badge badge-crit'>Error</span></td></tr>"
        } else {
            $expiryStr = if ($r.Expiry) { $r.Expiry.ToString('yyyy-MM-dd HH:mm') } else { 'N/A' }
            $daysStr   = if ($null -ne $r.DaysLeft) { "$($r.DaysLeft)" } else { 'N/A' }
            $sslRows += "<tr><td><strong>$(HtmlEncode $r.Hostname)</strong>:$($r.Port)</td><td><code>$(HtmlEncode $r.Subject)</code></td><td>$expiryStr</td><td>$daysStr</td><td><span class='badge $badge'>$(HtmlEncode $r.Status)</span></td></tr>"
        }
    }
    $sslSection = @"
<div class="section-title">SSL/TLS Remote Certificate Checks ($($sslResults.Count) host(s))</div>
<table>
  <thead><tr><th>Host:Port</th><th>Subject</th><th>Expiry</th><th>Days Left</th><th>Status</th></tr></thead>
  <tbody>$sslRows</tbody>
</table>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>R.E.L.I.C. Certificates -- $env:COMPUTERNAME</title>
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
<h1>R.E.L.I.C. -- Certificate Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card"><div class="val">$($localCerts.Count)</div><div class="lbl">Total Certs</div></div>
  <div class="card crit"><div class="val">$expiredCount</div><div class="lbl">Expired</div></div>
  <div class="card crit"><div class="val">$critCount</div><div class="lbl">Critical (&lt;30d)</div></div>
  <div class="card warn"><div class="val">$warnCount</div><div class="lbl">Warning (&lt;90d)</div></div>
  <div class="card ok"><div class="val">$healthyCount</div><div class="lbl">Healthy</div></div>
  <div class="card"><div class="val">$($sslResults.Count)</div><div class="lbl">SSL Hosts</div></div>
</div>

<div class="section-title">Local Certificate Stores ($($localCerts.Count) certificate(s))</div>
<table>
  <thead><tr><th>Store</th><th>Subject</th><th>Issuer</th><th>Expiry</th><th>Days Left</th><th>Status</th></tr></thead>
  <tbody>$localRows</tbody>
</table>

$sslSection

<div class="footer">
  Generated by R.E.L.I.C. -- Technician Toolkit LiveConnect Suite. Stores audited: My, CA, Root, TrustedPublisher.
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
Write-Host "[OK] R.E.L.I.C. complete." -ForegroundColor Cyan
Write-Host ""
