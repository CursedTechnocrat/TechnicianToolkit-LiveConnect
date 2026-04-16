<#
.SYNOPSIS
    A.U.D.I.T. — Automated User Detection, Inspection & Triage
    LiveConnect-Compatible Local Account Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Audits all local user accounts on the machine. Reports account status,
    last logon time, password configuration, group memberships, and flags
    potentially risky accounts. Exports a dark-themed HTML report to the
    specified path.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\audit.ps1
    PS C:\> .\audit.ps1 -ReportPath "C:\Temp"
    PS C:\> .\audit.ps1 -ReportPath "\\server\share\Reports"

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

$ExecutionTime   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename  = "AUDIT_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

# Ensure report folder exists
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
Write-Host "  A.U.D.I.T. -- Automated User Detection, Inspection & Triage" -ForegroundColor Cyan
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

function Get-AdminMembers {
    try {
        $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop
        return $admins | ForEach-Object { ($_.Name -split '\\')[-1] }
    }
    catch {
        return @()
    }
}

function Get-AccountData {
    param([string[]]$AdminNames)

    $staleDays = 90
    $staleDate = (Get-Date).AddDays(-$staleDays)
    $accounts  = @()

    $localUsers = Get-LocalUser -ErrorAction SilentlyContinue

    foreach ($user in $localUsers) {
        $isAdmin   = $AdminNames -contains $user.Name
        $lastLogon = if ($user.LastLogon) { $user.LastLogon } else { $null }

        $flags = @()

        if ($user.Enabled -and -not $user.PasswordRequired) {
            $flags += "No password required"
        }
        if ($user.Enabled -and -not $user.PasswordLastSet) {
            $flags += "Password never set"
        }
        if ($user.Enabled -and (-not $lastLogon -or $lastLogon -lt $staleDate)) {
            $flags += "Stale (>$staleDays days)"
        }
        if (-not $user.Enabled) {
            $flags += "Disabled"
        }

        $accounts += [PSCustomObject]@{
            Name             = $user.Name
            FullName         = $user.FullName
            Enabled          = $user.Enabled
            IsAdmin          = $isAdmin
            LastLogon        = if ($lastLogon) { $lastLogon.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
            PasswordLastSet  = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd") } else { "Never" }
            PasswordExpires  = if ($user.PasswordExpires) { $user.PasswordExpires.ToString("yyyy-MM-dd") } else { "Never / No Expiry" }
            PasswordRequired = $user.PasswordRequired
            Description      = $user.Description
            Flags            = if ($flags.Count -gt 0) { $flags -join '; ' } else { "" }
        }
    }

    return $accounts
}

# ===========================
# AUDIT EXECUTION
# ===========================

Write-Host "[*] Resolving Administrators group members..." -ForegroundColor Magenta
$adminNames = Get-AdminMembers

Write-Host "[*] Enumerating local user accounts..." -ForegroundColor Magenta
$accounts = Get-AccountData -AdminNames $adminNames

Write-Host "[OK] Found $($accounts.Count) local user account(s)." -ForegroundColor Green
Write-Host ""

# Console summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ACCOUNT OVERVIEW" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($acct in ($accounts | Sort-Object IsAdmin -Descending)) {
    $statusColor = if ($acct.Enabled) { 'Green' } else { 'Gray' }
    $roleLabel   = if ($acct.IsAdmin) { " [ADMIN]" } else { "" }

    Write-Host ("  {0,-28} Enabled: {1,-6} Last Logon: {2}" -f `
        ($acct.Name + $roleLabel), $acct.Enabled, $acct.LastLogon) -ForegroundColor $statusColor

    if ($acct.Flags) {
        Write-Host ("  {0,-28} [!!] {1}" -f "", $acct.Flags) -ForegroundColor Yellow
    }
}

# Flagged accounts callout
$flagged = $accounts | Where-Object { $_.Flags }
if ($flagged.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  FLAGGED ACCOUNTS ($($flagged.Count))" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    foreach ($acct in $flagged) {
        Write-Host "  $($acct.Name)" -ForegroundColor Yellow
        Write-Host "    $($acct.Flags)" -ForegroundColor Gray
    }
}

# ===========================
# HTML REPORT GENERATION
# ===========================

Write-Host ""
Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$totalAccounts = $accounts.Count
$enabledCount  = ($accounts | Where-Object {  $_.Enabled  } | Measure-Object).Count
$disabledCount = ($accounts | Where-Object { -not $_.Enabled } | Measure-Object).Count
$adminCount    = ($accounts | Where-Object {  $_.IsAdmin  } | Measure-Object).Count
$flaggedCount  = ($accounts | Where-Object {  $_.Flags    } | Measure-Object).Count

# Build account rows
$rows = ""
foreach ($acct in ($accounts | Sort-Object IsAdmin -Descending)) {
    $enabledBadge = if ($acct.Enabled) {
        "<span class='badge badge-ok'>Enabled</span>"
    } else {
        "<span class='badge badge-warn'>Disabled</span>"
    }
    $adminBadge = if ($acct.IsAdmin) {
        "<span class='badge badge-crit'>Admin</span>"
    } else {
        "<span class='badge badge-neutral'>Standard</span>"
    }
    $flagCell = if ($acct.Flags) {
        "<span class='flag'>$([System.Web.HttpUtility]::HtmlEncode($acct.Flags))</span>"
    } else { "" }

    $rows += @"
        <tr>
            <td><strong>$([System.Web.HttpUtility]::HtmlEncode($acct.Name))</strong></td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($acct.FullName))</td>
            <td>$enabledBadge</td>
            <td>$adminBadge</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($acct.LastLogon))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($acct.PasswordLastSet))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($acct.PasswordExpires))</td>
            <td>$flagCell</td>
        </tr>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>A.U.D.I.T. Account Audit -- $env:COMPUTERNAME</title>
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
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: bold; }
  .badge-ok      { background: #1a4a2e; color: #2ecc71; }
  .badge-warn    { background: #4a3a10; color: #f39c12; }
  .badge-crit    { background: #4a1a1a; color: #e74c3c; }
  .badge-neutral { background: #2a2a3e; color: #aaa; }
  .flag { color: #f39c12; font-size: 12px; }
  .section-title { color: #00d4ff; font-size: 15px; margin: 28px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>A.U.D.I.T. -- Account Audit Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card"><div class="val">$totalAccounts</div><div class="lbl">Total Accounts</div></div>
  <div class="card ok"><div class="val">$enabledCount</div><div class="lbl">Enabled</div></div>
  <div class="card"><div class="val">$disabledCount</div><div class="lbl">Disabled</div></div>
  <div class="card warn"><div class="val">$adminCount</div><div class="lbl">Administrators</div></div>
  <div class="card crit"><div class="val">$flaggedCount</div><div class="lbl">Flagged</div></div>
</div>

<div class="section-title">Local User Accounts</div>
<table>
  <thead>
    <tr>
      <th>Username</th>
      <th>Full Name</th>
      <th>Status</th>
      <th>Role</th>
      <th>Last Logon</th>
      <th>Password Set</th>
      <th>Password Expires</th>
      <th>Flags</th>
    </tr>
  </thead>
  <tbody>
    $rows
  </tbody>
</table>

<div class="footer">
  Generated by A.U.D.I.T. -- Technician Toolkit LiveConnect Suite &nbsp;|&nbsp; Stale threshold: 90 days without logon
</div>
</body>
</html>
"@

try {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    [System.IO.File]::WriteAllText($reportFullPath, $html, [System.Text.Encoding]::UTF8)
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
Write-Host "  AUDIT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Accounts : $totalAccounts" -ForegroundColor Gray
Write-Host "  Enabled        : $enabledCount" -ForegroundColor Green
Write-Host "  Disabled       : $disabledCount" -ForegroundColor Gray
Write-Host "  Administrators : $adminCount" -ForegroundColor Yellow
Write-Host "  Flagged        : $flaggedCount" -ForegroundColor $(if ($flaggedCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  REPORT PATH: $reportFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] A.U.D.I.T. complete." -ForegroundColor Cyan
Write-Host ""
