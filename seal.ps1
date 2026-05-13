<#
.SYNOPSIS
    S.E.A.L. — Secure Element Audit Log
    LiveConnect-Compatible TPM Health Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Audits the state of the Trusted Platform Module -- presence, specification
    version, manufacturer & firmware, ownership, clear state, attestation
    readiness -- and cross-references against BitLocker to confirm which
    volumes depend on the TPM's protector chain. Produces a dark-themed HTML
    report with a red/yellow/green readiness verdict suitable for a Windows 11,
    Autopilot, or BitLocker readiness gate.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\seal.ps1
    PS C:\> .\seal.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : T.O.T.E.M. (main toolkit)
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
$reportFilename = "SEAL_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  S.E.A.L. -- Secure Element Audit Log" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine   : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As    : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time      : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Report    : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

# ===========================
# HELPERS
# ===========================

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function YesNoBadge([bool]$b) {
    if ($b) { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-crit'>No</span>" }
}

# ===========================
# COLLECTORS
# ===========================

function Get-TpmStatus {
    $tpm = $null
    try { $tpm = Get-Tpm -ErrorAction Stop }
    catch {
        return [PSCustomObject]@{
            Present = $false; Ready = $false; Enabled = $false; Activated = $false; Owned = $false
            ManufacturerId = $null; ManufacturerName = $null; ManufacturerVersion = $null
            SpecVersion = $null; PhysicalPresence = $null; AutoProvisioning = $null
            RestartPending = $false; CollectorError = $_.Exception.Message
        }
    }
    return [PSCustomObject]@{
        Present             = [bool]$tpm.TpmPresent
        Ready               = [bool]$tpm.TpmReady
        Enabled             = [bool]$tpm.TpmEnabled
        Activated           = [bool]$tpm.TpmActivated
        Owned               = [bool]$tpm.TpmOwned
        ManufacturerId      = $tpm.ManufacturerId
        ManufacturerName    = $tpm.ManufacturerIdTxt
        ManufacturerVersion = $tpm.ManufacturerVersion
        SpecVersion         = $tpm.SpecVersion
        PhysicalPresence    = $tpm.PhysicalPresenceVersionInfo
        AutoProvisioning    = if ($null -ne $tpm.AutoProvisioning) { $tpm.AutoProvisioning.ToString() } else { 'Unknown' }
        RestartPending      = [bool]$tpm.RestartPending
        CollectorError      = $null
    }
}

function Get-TpmVersionSummary {
    param($Tpm)
    $spec = 'Unknown'
    if ($Tpm.SpecVersion) {
        $first = ($Tpm.SpecVersion -split ',')[0].Trim()
        if ($first) { $spec = $first }
    }
    $label = switch ($spec) { '2.0' { 'TPM 2.0' } '1.2' { 'TPM 1.2' } default { "TPM $spec" } }
    return [PSCustomObject]@{
        SpecVersion  = $spec
        Label        = $label
        IsWin11Ready = ($spec -eq '2.0')
    }
}

function Get-BitLockerTpmDependency {
    $result = @()
    try { $vols = Get-BitLockerVolume -ErrorAction Stop }
    catch { return @() }
    foreach ($v in $vols) {
        $tpmProtectors = @($v.KeyProtector | Where-Object {
            $_.KeyProtectorType -in @('Tpm','TpmPin','TpmPinStartupKey','TpmStartupKey')
        })
        $result += [PSCustomObject]@{
            MountPoint        = $v.MountPoint
            VolumeType        = "$($v.VolumeType)"
            ProtectionStatus  = "$($v.ProtectionStatus)"
            EncryptionMethod  = "$($v.EncryptionMethod)"
            Protectors        = (@($v.KeyProtector | Select-Object -ExpandProperty KeyProtectorType) -join ', ')
            TpmProtectorCount = $tpmProtectors.Count
            DependsOnTpm      = ($tpmProtectors.Count -gt 0)
        }
    }
    return @($result)
}

function Get-TpmAttestationInfo {
    $result = [PSCustomObject]@{ EkPresent = $null; EkAlgorithms = $null; CollectorError = $null }
    try {
        $ek = Get-TpmEndorsementKeyInfo -ErrorAction Stop
        if ($ek) {
            $result.EkPresent = $true
            $algos = @()
            if ($ek.IsPresent) { $algos += 'EK present' }
            if ($ek.ManufacturerCertificates -and $ek.ManufacturerCertificates.Count -gt 0) {
                $algos += "$($ek.ManufacturerCertificates.Count) manufacturer cert(s)"
            }
            $result.EkAlgorithms = ($algos -join '; ')
        } else { $result.EkPresent = $false }
    } catch {
        $result.EkPresent      = $null
        $result.CollectorError = $_.Exception.Message
    }
    return $result
}

function Get-Verdict {
    param($Tpm, $Version, [array]$BitLockerDependencies, $Attestation)
    $issues = @(); $warns = @()
    if (-not $Tpm.Present) {
        $issues += 'No TPM is present on this machine — Windows 11 upgrade and BitLocker key protection are blocked.'
    } else {
        if (-not $Tpm.Enabled)   { $issues += 'TPM is present but DISABLED in firmware — enable in BIOS/UEFI Security settings.' }
        if (-not $Tpm.Activated) { $issues += 'TPM is DEACTIVATED — activate in BIOS/UEFI and take ownership.' }
        if (-not $Tpm.Ready)     { $warns  += 'TPM reports NOT READY — may need Initialize-Tpm to provision, or a clear-and-reprovision cycle.' }
        if (-not $Tpm.Owned)     { $warns  += 'TPM has no owner — BitLocker provisioning will handle this on first encrypt, but document the state before proceeding.' }
        if ($Tpm.RestartPending) { $warns  += 'TPM reports a pending restart — commit outstanding state changes before audit-time conclusions.' }
        if (-not $Version.IsWin11Ready) {
            $warns += "This machine has $($Version.Label), not TPM 2.0 — Windows 11 upgrade is blocked until firmware offers a 2.0-capable chip (vendor BIOS update or dTPM->fTPM toggle may help)."
        }
    }
    $dependent    = @($BitLockerDependencies | Where-Object { $_.DependsOnTpm })
    $anyBitLocker = @($BitLockerDependencies | Where-Object { $_.ProtectionStatus -eq 'On' }).Count
    if ($Tpm.Present -and $Tpm.Ready -and $dependent.Count -eq 0 -and $anyBitLocker -gt 0) {
        $warns += 'BitLocker is enabled but none of the protected volumes use a TPM-based key protector — consider adding TPM for seamless unlock.'
    }
    if ($null -eq $Attestation.EkPresent -and $Tpm.Present) {
        $warns += 'Endorsement Key info could not be read — Autopilot device pre-registration and attested boot will fail until the EK is retrievable.'
    }
    $verdict = if ($issues.Count -gt 0) { 'NOT READY' } elseif ($warns.Count -gt 0) { 'READY WITH WARNINGS' } else { 'READY' }
    $class   = if ($issues.Count -gt 0) { 'crit' } elseif ($warns.Count -gt 0) { 'warn' } else { 'ok' }
    return [PSCustomObject]@{
        Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns)
        BitLockerVolumesDependingOnTpm = $dependent.Count
    }
}

# ===========================
# RUN COLLECTORS
# ===========================

Write-Host "[*] Reading TPM status..." -ForegroundColor Magenta
$tpm = Get-TpmStatus
if ($tpm.CollectorError) {
    Write-Host "[ERROR] Get-Tpm failed: $($tpm.CollectorError)" -ForegroundColor Red
} else {
    $presentColor = if ($tpm.Present) { 'Green' } else { 'Red' }
    Write-Host ("  Present   : {0}" -f $tpm.Present) -ForegroundColor $presentColor
    if ($tpm.Present) {
        Write-Host ("  Enabled   : {0}" -f $tpm.Enabled)   -ForegroundColor $(if ($tpm.Enabled)   { 'Green' } else { 'Red' })
        Write-Host ("  Activated : {0}" -f $tpm.Activated) -ForegroundColor $(if ($tpm.Activated) { 'Green' } else { 'Red' })
        Write-Host ("  Ready     : {0}" -f $tpm.Ready)     -ForegroundColor $(if ($tpm.Ready)     { 'Green' } else { 'Yellow' })
        Write-Host ("  Owned     : {0}" -f $tpm.Owned)     -ForegroundColor $(if ($tpm.Owned)     { 'Green' } else { 'Yellow' })
        Write-Host ("  Mfr       : {0}" -f $tpm.ManufacturerName) -ForegroundColor Gray
    }
}

$version = Get-TpmVersionSummary -Tpm $tpm
Write-Host ""
Write-Host "[*] Specification..." -ForegroundColor Magenta
Write-Host ("  {0}  (raw: {1})" -f $version.Label, $version.SpecVersion) -ForegroundColor $(if ($version.IsWin11Ready) { 'Green' } else { 'Yellow' })

Write-Host ""
Write-Host "[*] BitLocker dependency..." -ForegroundColor Magenta
$bitLocker = Get-BitLockerTpmDependency
if ($bitLocker.Count -eq 0) {
    Write-Host "  No BitLocker volumes found (or BitLocker module unavailable)." -ForegroundColor Yellow
} else {
    foreach ($v in $bitLocker) {
        $depLabel = if ($v.DependsOnTpm) { "uses TPM ($($v.TpmProtectorCount))" } else { 'no TPM protector' }
        $color    = if ($v.ProtectionStatus -eq 'On' -and $v.DependsOnTpm) { 'Green' }
                    elseif ($v.ProtectionStatus -eq 'On') { 'Yellow' } else { 'Gray' }
        Write-Host ("  {0,-4} {1,-16} Protection: {2,-3}  Protectors: {3}  ({4})" -f `
            $v.MountPoint, $v.VolumeType, $v.ProtectionStatus, $v.Protectors, $depLabel) -ForegroundColor $color
    }
}

Write-Host ""
Write-Host "[*] Endorsement Key..." -ForegroundColor Magenta
$attestation = Get-TpmAttestationInfo
if ($attestation.EkPresent) {
    Write-Host "[OK] Endorsement Key info readable: $($attestation.EkAlgorithms)" -ForegroundColor Green
} elseif ($null -eq $attestation.EkPresent) {
    Write-Host "[!!] Could not read EK info: $($attestation.CollectorError)" -ForegroundColor Yellow
} else {
    Write-Host "[!!] No Endorsement Key data available from TPM." -ForegroundColor Red
}

$verdict = Get-Verdict -Tpm $tpm -Version $version -BitLockerDependencies $bitLocker -Attestation $attestation

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TPM READINESS VERDICT" -ForegroundColor Cyan
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

$blRows = ""
if ($bitLocker.Count -eq 0) {
    $blRows = "<tr><td colspan='5' style='text-align:center;color:#888;'>No BitLocker-managed volumes found.</td></tr>"
} else {
    foreach ($v in $bitLocker) {
        $protState = switch ($v.ProtectionStatus) {
            'On'  { "<span class='badge badge-ok'>On</span>" }
            'Off' { "<span class='badge badge-warn'>Off</span>" }
            default { "<span class='badge badge-neutral'>$(HtmlEncode $v.ProtectionStatus)</span>" }
        }
        $tpmDep = if ($v.DependsOnTpm) { "<span class='badge badge-ok'>Yes ($($v.TpmProtectorCount))</span>" } else { "<span class='badge badge-warn'>No</span>" }
        $blRows += @"
        <tr>
            <td>$(HtmlEncode $v.MountPoint)</td>
            <td>$(HtmlEncode $v.VolumeType)</td>
            <td>$protState</td>
            <td>$(HtmlEncode $v.Protectors)</td>
            <td>$tpmDep</td>
        </tr>
"@
    }
}

$verdictItems = ""
foreach ($i in $verdict.Issues) { $verdictItems += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $verdictItems += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $verdictItems = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>TPM posture is clean for Windows 11, BitLocker, and Autopilot.</li>"
}

$specBadgeClass = if ($version.IsWin11Ready) { 'badge-ok' } else { 'badge-warn' }
$collectorErrCell = if ($tpm.CollectorError) {
    "<tr><th>Collector Error</th><td><span class='badge badge-crit'>$(HtmlEncode $tpm.CollectorError)</span></td></tr>"
} else { '' }
$attErrCell = if ($attestation.CollectorError) {
    "<tr><th>EK Read Error</th><td><span class='badge badge-warn'>$(HtmlEncode $attestation.CollectorError)</span></td></tr>"
} else { '' }

$ekCellHtml = if ($attestation.EkPresent) {
    "<span class='badge badge-ok'>Yes</span>"
} elseif ($null -eq $attestation.EkPresent) {
    "<span class='badge badge-warn'>Unknown</span>"
} else {
    "<span class='badge badge-crit'>No</span>"
}

$ekSummaryCellHtml = if ($attestation.EkPresent) { 'Yes' }
                     elseif ($null -eq $attestation.EkPresent) { 'Unknown' }
                     else { 'No' }
$ekSummaryClass = if ($attestation.EkPresent) { 'ok' }
                  elseif ($null -eq $attestation.EkPresent) { 'warn' }
                  else { 'crit' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>S.E.A.L. TPM Health -- $env:COMPUTERNAME</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', Consolas, monospace; font-size: 14px; padding: 24px; }
  h1 { color: #00d4ff; font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 24px; }
  .summary { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 28px; }
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
  .section-title { color: #00d4ff; font-size: 15px; margin: 28px 0 10px; border-bottom: 1px solid #0f3460; padding-bottom: 6px; }
  ul { list-style: none; padding-left: 0; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>S.E.A.L. -- TPM Health Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">TPM Readiness</div></div>
  <div class="card $(if ($tpm.Present) { 'ok' } else { 'crit' })"><div class="val">$(if ($tpm.Present) { 'Present' } else { 'Absent' })</div><div class="lbl">TPM Hardware</div></div>
  <div class="card"><div class="val">$(HtmlEncode $version.Label)</div><div class="lbl">Specification</div></div>
  <div class="card $(if ($tpm.Ready) { 'ok' } else { 'warn' })"><div class="val">$(if ($tpm.Ready) { 'Yes' } else { 'No' })</div><div class="lbl">TPM Ready</div></div>
  <div class="card"><div class="val">$($verdict.BitLockerVolumesDependingOnTpm)</div><div class="lbl">BitLocker Vols Using TPM</div></div>
  <div class="card $ekSummaryClass"><div class="val">$ekSummaryCellHtml</div><div class="lbl">Endorsement Key</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$verdictItems</ul>

<div class="section-title">TPM Status</div>
<table>
  <tbody>
    <tr><th>Present</th><td>$(YesNoBadge $tpm.Present)</td></tr>
    <tr><th>Enabled (firmware)</th><td>$(YesNoBadge $tpm.Enabled)</td></tr>
    <tr><th>Activated</th><td>$(YesNoBadge $tpm.Activated)</td></tr>
    <tr><th>Ready for Use</th><td>$(YesNoBadge $tpm.Ready)</td></tr>
    <tr><th>Owned</th><td>$(YesNoBadge $tpm.Owned)</td></tr>
    <tr><th>Specification</th><td><span class='badge $specBadgeClass'>$(HtmlEncode $version.Label)</span></td></tr>
    <tr><th>Manufacturer (raw ID)</th><td><code>$(HtmlEncode "$($tpm.ManufacturerId)")</code></td></tr>
    <tr><th>Manufacturer (text)</th><td>$(HtmlEncode "$($tpm.ManufacturerName)")</td></tr>
    <tr><th>Manufacturer Version</th><td><code>$(HtmlEncode "$($tpm.ManufacturerVersion)")</code></td></tr>
    <tr><th>Physical Presence Version</th><td>$(HtmlEncode "$($tpm.PhysicalPresence)")</td></tr>
    <tr><th>Auto-Provisioning</th><td>$(HtmlEncode "$($tpm.AutoProvisioning)")</td></tr>
    <tr><th>Restart Pending</th><td>$(YesNoBadge $tpm.RestartPending)</td></tr>
    $collectorErrCell
  </tbody>
</table>

<div class="section-title">BitLocker Dependency on TPM ($($bitLocker.Count) volume(s))</div>
<table>
  <thead><tr><th>Mount</th><th>Volume Type</th><th>Protection</th><th>Protectors</th><th>Uses TPM?</th></tr></thead>
  <tbody>$blRows</tbody>
</table>

<div class="section-title">Attestation / Endorsement Key</div>
<table>
  <tbody>
    <tr><th>EK Present</th><td>$ekCellHtml</td></tr>
    <tr><th>EK Details</th><td>$(HtmlEncode "$($attestation.EkAlgorithms)")</td></tr>
    $attErrCell
  </tbody>
</table>

<div class="footer">
  Generated by S.E.A.L. -- Technician Toolkit LiveConnect Suite
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
Write-Host "[OK] S.E.A.L. complete." -ForegroundColor Cyan
Write-Host ""
