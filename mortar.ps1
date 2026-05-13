<#
.SYNOPSIS
    M.O.R.T.A.R. — Motherboard, Onboard ROM & TPM/UEFI Audit Report
    LiveConnect-Compatible BIOS / UEFI / Firmware Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Inventories system identity, BIOS / UEFI state, Secure Boot posture, and
    vendor-specific firmware-update channel availability (Dell Command, HP
    HPIA / HPSA, Lenovo Vantage / System Update, Microsoft Surface). Optionally
    scans Windows Update for pending firmware/driver updates if the
    PSWindowsUpdate module is already installed.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\mortar.ps1
    PS C:\> .\mortar.ps1 -ReportPath "C:\Temp"
    PS C:\> .\mortar.ps1 -ScanWindowsUpdate

.PARAMETERS
    -ReportPath          Folder where the HTML report is saved (default: C:\Temp)
    -ScanWindowsUpdate   Scan WU for pending driver/firmware updates. Requires
                         PSWindowsUpdate already installed; never auto-installs.

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : A.N.V.I.L. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [switch]$ScanWindowsUpdate
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "MORTAR_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  M.O.R.T.A.R. -- Motherboard, Onboard ROM & TPM/UEFI Audit Report" -ForegroundColor Cyan
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
    if ($null -eq $b -or $b -le 0) { return '—' }
    $units = 'B','KB','MB','GB','TB'; $i = 0
    while ($b -ge 1024 -and $i -lt $units.Count - 1) { $b = $b / 1024; $i++ }
    return ('{0:N1} {1}' -f $b, $units[$i])
}

# ===========================
# COLLECTORS
# ===========================

function Get-SystemInfo {
    $cs   = Get-CimInstance -ClassName Win32_ComputerSystem        -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS                  -ErrorAction SilentlyContinue
    $sys  = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue

    $releaseDate = $null
    if ($bios -and $bios.ReleaseDate) {
        try { $releaseDate = [Management.ManagementDateTimeConverter]::ToDateTime($bios.ReleaseDate) } catch {}
    }
    $biosAgeDays = if ($releaseDate) { [math]::Round(((Get-Date) - $releaseDate).TotalDays, 0) } else { $null }

    $mfr = if ($cs -and $cs.Manufacturer) { $cs.Manufacturer } else { '' }
    $vendor = switch -Wildcard ($mfr.ToLower()) {
        '*dell*'      { 'Dell' }
        '*hp*'        { 'HP' }
        '*hewlett*'   { 'HP' }
        '*lenovo*'    { 'Lenovo' }
        '*microsoft*' { 'Microsoft' }
        default       { 'Other' }
    }

    return [PSCustomObject]@{
        Manufacturer    = $mfr
        Vendor          = $vendor
        Model           = if ($cs) { $cs.Model } else { '' }
        SystemSKU       = if ($sys) { $sys.IdentifyingNumber } else { '' }
        UUID            = if ($sys) { $sys.UUID } else { '' }
        SerialNumber    = if ($bios) { $bios.SerialNumber } else { '' }
        BIOSVendor      = if ($bios) { $bios.Manufacturer } else { '' }
        BIOSVersion     = if ($bios) { $bios.SMBIOSBIOSVersion } else { '' }
        BIOSReleaseDate = $releaseDate
        BIOSAgeDays     = $biosAgeDays
    }
}

function Get-UefiPosture {
    $bootMode = 'Unknown'
    try {
        $sysDisk = Get-Disk | Where-Object { $_.IsSystem } | Select-Object -First 1
        if ($sysDisk) {
            $bootMode = if ($sysDisk.PartitionStyle -eq 'GPT') { 'UEFI' } else { 'Legacy/BIOS' }
        }
    } catch {}

    $firmwareType = 'Unknown'
    try {
        $env = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction SilentlyContinue
        if ($env -and $env.PEFirmwareType) {
            $firmwareType = switch ([int]$env.PEFirmwareType) {
                1 { 'BIOS (legacy)' } 2 { 'UEFI' } default { "Unknown ($($env.PEFirmwareType))" }
            }
        }
    } catch {}

    $secureBoot = $null
    try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue } catch {}

    return [PSCustomObject]@{
        BootMode        = $bootMode
        FirmwareType    = $firmwareType
        SecureBootState = if ($null -eq $secureBoot) { 'Unsupported' } elseif ($secureBoot) { 'Enabled' } else { 'Disabled' }
        SecureBoot      = $secureBoot
    }
}

$script:VendorChannels = @(
    @{ Vendor = 'Dell';      Name = 'Dell Command | Update (CLI)';      Paths = @('C:\Program Files\Dell\CommandUpdate\dcu-cli.exe','C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe') }
    @{ Vendor = 'Dell';      Name = 'Dell Command | Update (GUI)';      Paths = @('C:\Program Files\Dell\CommandUpdate\DellCommandUpdate.exe','C:\Program Files (x86)\Dell\CommandUpdate\DellCommandUpdate.exe') }
    @{ Vendor = 'HP';        Name = 'HP Image Assistant (HPIA)';        Paths = @('C:\Program Files\HP\HPIA\HPImageAssistant.exe','C:\SWSetup\HPIA\HPImageAssistant.exe') }
    @{ Vendor = 'HP';        Name = 'HP Support Assistant';             Paths = @('C:\Program Files (x86)\Hewlett-Packard\HP Support Solutions\HPSF.exe') }
    @{ Vendor = 'Lenovo';    Name = 'Lenovo System Update (Tvsu)';      Paths = @('C:\Program Files (x86)\Lenovo\System Update\Tvsu.exe') }
    @{ Vendor = 'Lenovo';    Name = 'Lenovo Vantage';                   Paths = @("$env:LOCALAPPDATA\Packages\E046963F.LenovoSettingsforEnterprise_k1h2ywk1493x8") }
    @{ Vendor = 'Microsoft'; Name = 'Surface UEFI Configurator (SEMM)'; Paths = @('C:\Program Files (x86)\Microsoft\Surface\UefiConfigurator\UEFIConfigurator.exe') }
)

function Get-VendorChannelStatus {
    param([string]$Vendor)
    $applicable = $script:VendorChannels | Where-Object { $_.Vendor -eq $Vendor -or $Vendor -eq 'Other' }
    if (-not $applicable) {
        return @([PSCustomObject]@{ Name = "(no known firmware-update channel for '$Vendor')"; Vendor = $Vendor; Found = $false; Path = '' })
    }
    $rows = foreach ($ch in $applicable) {
        $foundPath = $null
        foreach ($p in $ch.Paths) { if (Test-Path $p) { $foundPath = $p; break } }
        [PSCustomObject]@{ Name = $ch.Name; Vendor = $ch.Vendor; Found = [bool]$foundPath; Path = if ($foundPath) { $foundPath } else { '(not installed)' } }
    }
    return @($rows)
}

function Get-PendingFirmwareUpdates {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "[!!] PSWindowsUpdate not installed; skipping WU driver/firmware scan." -ForegroundColor Yellow
        return @()
    }
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        $updates = Get-WindowsUpdate -Category 'Drivers' -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] WU driver scan failed: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
    if (-not $updates -or $updates.Count -eq 0) { return @() }
    $rows = foreach ($u in $updates) {
        [PSCustomObject]@{
            Title    = $u.Title
            KB       = if ($u.KB) { $u.KB } else { '—' }
            Size     = if ($u.Size) { Format-Bytes $u.Size } else { '—' }
            Severity = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { 'Optional' }
        }
    }
    return @($rows)
}

function Get-Verdict {
    param($System, $Uefi, [array]$Channels, [array]$Pending)
    $issues = @(); $warns = @()

    if ($Uefi.FirmwareType -like 'BIOS*') {
        $issues += 'Machine is booting in legacy BIOS mode — Secure Boot and modern OS requirements (Windows 11, BitLocker PCR-7) need UEFI.'
    }
    if ($Uefi.SecureBootState -eq 'Disabled') {
        $issues += 'Secure Boot is disabled — required for Windows 11 and many security baselines.'
    } elseif ($Uefi.SecureBootState -eq 'Unsupported') {
        $warns += 'Secure Boot unsupported — the firmware does not expose UEFI variables; likely legacy BIOS.'
    }
    if ($System.BIOSAgeDays -and $System.BIOSAgeDays -ge 730) {
        $warns += "BIOS is $([math]::Round($System.BIOSAgeDays / 365, 1)) years old ($($System.BIOSReleaseDate.ToString('yyyy-MM-dd'))) — review the vendor release channel for a newer version."
    }
    $installedChannels = @($Channels | Where-Object { $_.Found })
    if ($System.Vendor -ne 'Other' -and $installedChannels.Count -eq 0) {
        $warns += "No $($System.Vendor) firmware-update tooling detected — deploying DCU / HPIA / Lenovo System Update / Vantage makes firmware maintenance trackable."
    }
    if ($Pending.Count -gt 0) {
        $warns += "$($Pending.Count) pending driver/firmware update(s) are available via Windows Update."
    }

    $verdict = if ($issues.Count -gt 0) { 'ATTENTION REQUIRED' } elseif ($warns.Count -gt 0) { 'REVIEW RECOMMENDED' } else { 'READY' }
    $class   = if ($issues.Count -gt 0) { 'crit' }              elseif ($warns.Count -gt 0) { 'warn' }              else { 'ok' }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Reading system identity..." -ForegroundColor Magenta
$system = Get-SystemInfo
Write-Host ("  Manufacturer: {0} ({1})" -f $system.Manufacturer, $system.Vendor) -ForegroundColor Gray
Write-Host ("  Model       : {0}" -f $system.Model)        -ForegroundColor Gray
Write-Host ("  Serial      : {0}" -f $system.SerialNumber) -ForegroundColor Gray
Write-Host ("  BIOS        : {0} v{1}" -f $system.BIOSVendor, $system.BIOSVersion) -ForegroundColor Gray
if ($system.BIOSReleaseDate) {
    $age   = [math]::Round($system.BIOSAgeDays / 365, 1)
    $color = if ($system.BIOSAgeDays -ge 730) { 'Yellow' } else { 'Green' }
    Write-Host ("  BIOS released {0} ({1} yr old)" -f $system.BIOSReleaseDate.ToString('yyyy-MM-dd'), $age) -ForegroundColor $color
}
Write-Host ""

Write-Host "[*] Reading UEFI / Secure Boot posture..." -ForegroundColor Magenta
$uefi = Get-UefiPosture
$fwColor = if ($uefi.FirmwareType -eq 'UEFI') { 'Green' } elseif ($uefi.FirmwareType -like 'BIOS*') { 'Red' } else { 'Yellow' }
Write-Host ("  Firmware Type : {0}" -f $uefi.FirmwareType) -ForegroundColor $fwColor
Write-Host ("  Boot Mode     : {0}" -f $uefi.BootMode)     -ForegroundColor Gray
$sbColor = if ($uefi.SecureBootState -eq 'Enabled') { 'Green' } elseif ($uefi.SecureBootState -eq 'Disabled') { 'Red' } else { 'Yellow' }
Write-Host ("  Secure Boot   : {0}" -f $uefi.SecureBootState) -ForegroundColor $sbColor
Write-Host ""

Write-Host "[*] Reading vendor firmware channels..." -ForegroundColor Magenta
$channels = Get-VendorChannelStatus -Vendor $system.Vendor
foreach ($c in $channels) {
    $color = if ($c.Found) { 'Green' } else { 'Gray' }
    Write-Host ("  [{0,-10}] {1,-40} {2}" -f $c.Vendor, $c.Name, $(if ($c.Found) { 'Installed' } else { 'Not installed' })) -ForegroundColor $color
}
Write-Host ""

$pending = @()
if ($ScanWindowsUpdate) {
    Write-Host "[*] Scanning Windows Update for pending driver/firmware updates..." -ForegroundColor Magenta
    $pending = Get-PendingFirmwareUpdates
    if ($pending.Count -gt 0) {
        Write-Host "[!!] $($pending.Count) pending driver/firmware update(s)." -ForegroundColor Yellow
        foreach ($p in $pending) { Write-Host ("  [{0}] {1}" -f $p.Severity, $p.Title) -ForegroundColor Yellow }
    } else {
        Write-Host "[OK] No pending driver/firmware updates found." -ForegroundColor Green
    }
} else {
    Write-Host "[i] Windows Update scan skipped (pass -ScanWindowsUpdate to include)." -ForegroundColor Gray
}
Write-Host ""

$verdict = Get-Verdict -System $system -Uefi $uefi -Channels $channels -Pending $pending

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  FIRMWARE READINESS VERDICT" -ForegroundColor Cyan
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

$biosAgeStr  = if ($system.BIOSAgeDays)     { "$($system.BIOSAgeDays) days" } else { 'Unknown' }
$biosDateStr = if ($system.BIOSReleaseDate) { $system.BIOSReleaseDate.ToString('yyyy-MM-dd') } else { 'Unknown' }

$sbClass = switch ($uefi.SecureBootState) { 'Enabled' { 'badge-ok' } 'Disabled' { 'badge-crit' } 'Unsupported' { 'badge-warn' } default { 'badge-neutral' } }
$fwClass = if ($uefi.FirmwareType -eq 'UEFI') { 'badge-ok' } elseif ($uefi.FirmwareType -like 'BIOS*') { 'badge-crit' } else { 'badge-warn' }

$chRows = ""
foreach ($c in $channels) {
    $badge = if ($c.Found) { "<span class='badge badge-ok'>Installed</span>" } else { "<span class='badge badge-warn'>Not installed</span>" }
    $chRows += "<tr><td>$(HtmlEncode $c.Vendor)</td><td>$(HtmlEncode $c.Name)</td><td>$badge</td><td><code>$(HtmlEncode $c.Path)</code></td></tr>"
}

$pendingRows = ""
if ($pending.Count -eq 0) {
    $pendingRows = if ($ScanWindowsUpdate) {
        "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No pending driver/firmware updates.</td></tr>"
    } else {
        "<tr><td colspan='4' style='text-align:center;color:#888;'>Windows Update scan not requested (use -ScanWindowsUpdate to include).</td></tr>"
    }
} else {
    foreach ($p in $pending) {
        $pendingRows += "<tr><td>$(HtmlEncode $p.Title)</td><td>$(HtmlEncode $p.KB)</td><td>$(HtmlEncode $p.Size)</td><td>$(HtmlEncode $p.Severity)</td></tr>"
    }
}

$verdictBlock = ""
foreach ($i in $verdict.Issues) { $verdictBlock += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $verdictBlock += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $verdictBlock = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>Firmware posture is clean.</li>"
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>M.O.R.T.A.R. Firmware/BIOS -- $env:COMPUTERNAME</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', Consolas, monospace; font-size: 14px; padding: 24px; }
  h1 { color: #00d4ff; font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 24px; }
  .summary { display: flex; gap: 14px; flex-wrap: wrap; margin-bottom: 28px; }
  .card { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 16px 24px; min-width: 130px; text-align: center; }
  .card .val { font-size: 20px; font-weight: bold; color: #00d4ff; }
  .card .lbl { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-top: 4px; }
  .card.warn .val { color: #f39c12; }
  .card.crit .val { color: #e74c3c; }
  .card.ok   .val { color: #2ecc71; }
  table { width: 100%; border-collapse: collapse; margin-top: 8px; }
  th { background: #0f3460; color: #00d4ff; padding: 10px 12px; text-align: left; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
  td { padding: 9px 12px; border-bottom: 1px solid #1e2d4d; vertical-align: top; }
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
<h1>M.O.R.T.A.R. -- Firmware / BIOS Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Firmware Readiness</div></div>
  <div class="card"><div class="val">$(HtmlEncode $system.Vendor)</div><div class="lbl">Vendor</div></div>
  <div class="card $fwClass"><div class="val">$(HtmlEncode $uefi.FirmwareType)</div><div class="lbl">Firmware Type</div></div>
  <div class="card $sbClass"><div class="val">$(HtmlEncode $uefi.SecureBootState)</div><div class="lbl">Secure Boot</div></div>
  <div class="card"><div class="val">$biosAgeStr</div><div class="lbl">BIOS Age</div></div>
  <div class="card $(if ($pending.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($pending.Count)</div><div class="lbl">Pending WU Updates</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$verdictBlock</ul>

<div class="section-title">System Identity</div>
<table>
  <tbody>
    <tr><th>Manufacturer</th><td>$(HtmlEncode $system.Manufacturer)</td></tr>
    <tr><th>Model</th><td>$(HtmlEncode $system.Model)</td></tr>
    <tr><th>System SKU / Service Tag</th><td><code>$(HtmlEncode $system.SystemSKU)</code></td></tr>
    <tr><th>Serial Number</th><td><code>$(HtmlEncode $system.SerialNumber)</code></td></tr>
    <tr><th>UUID</th><td><code>$(HtmlEncode $system.UUID)</code></td></tr>
    <tr><th>BIOS Vendor</th><td>$(HtmlEncode $system.BIOSVendor)</td></tr>
    <tr><th>BIOS Version</th><td><code>$(HtmlEncode $system.BIOSVersion)</code></td></tr>
    <tr><th>BIOS Release Date</th><td>$biosDateStr</td></tr>
    <tr><th>BIOS Age</th><td>$biosAgeStr</td></tr>
  </tbody>
</table>

<div class="section-title">UEFI / Secure Boot</div>
<table>
  <tbody>
    <tr><th>Firmware Type</th><td><span class='badge $fwClass'>$(HtmlEncode $uefi.FirmwareType)</span></td></tr>
    <tr><th>Boot Mode (from system disk)</th><td>$(HtmlEncode $uefi.BootMode)</td></tr>
    <tr><th>Secure Boot State</th><td><span class='badge $sbClass'>$(HtmlEncode $uefi.SecureBootState)</span></td></tr>
  </tbody>
</table>

<div class="section-title">Vendor Firmware-Update Channels ($($channels.Count) channel(s))</div>
<table>
  <thead><tr><th>Vendor</th><th>Tool</th><th>Status</th><th>Path</th></tr></thead>
  <tbody>$chRows</tbody>
</table>

<div class="section-title">Pending Driver / Firmware Updates (Windows Update)</div>
<table>
  <thead><tr><th>Title</th><th>KB</th><th>Size</th><th>Severity</th></tr></thead>
  <tbody>$pendingRows</tbody>
</table>

<div class="footer">
  Generated by M.O.R.T.A.R. -- Technician Toolkit LiveConnect Suite
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
Write-Host "[OK] M.O.R.T.A.R. complete." -ForegroundColor Cyan
Write-Host ""
