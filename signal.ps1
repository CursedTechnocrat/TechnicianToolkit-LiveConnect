<#
.SYNOPSIS
    S.I.G.N.A.L. — Surveys Identified Guard Networks And Logs
    LiveConnect-Compatible Wi-Fi Profile Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Audits saved Wi-Fi (WLAN) profiles. Exports each profile to XML via
    `netsh wlan export profile ... key=clear`, parses the locale-stable
    schema, and produces a dark-themed HTML report covering authentication,
    cipher, connection mode, autoSwitch, hidden-SSID, and MAC-randomization
    for every profile, plus filtered tables for open, weak, and
    auto-connecting networks.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    Key material is masked by default. Pass -IncludeKey to render cleartext
    PSKs in the report (technician-managed audits only).

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\signal.ps1
    PS C:\> .\signal.ps1 -ReportPath "C:\Temp"
    PS C:\> .\signal.ps1 -IncludeKey

.PARAMETERS
    -ReportPath  Folder where the HTML report is saved (default: C:\Temp)
    -IncludeKey  Render cleartext PSKs in the HTML report (default: masked)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : B.E.A.C.O.N. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [switch]$IncludeKey
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "SIGNAL_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  S.I.G.N.A.L. -- Surveys Identified Guard Networks And Logs" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As     : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time       : $ExecutionTime" -ForegroundColor Gray
Write-Host "  IncludeKey : $([bool]$IncludeKey)" -ForegroundColor $(if ($IncludeKey) { 'Magenta' } else { 'Gray' })
Write-Host "  Report     : $reportFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
if ($IncludeKey) {
    Write-Host "  *** Key material WILL be rendered in cleartext (-IncludeKey) ***" -ForegroundColor Magenta
    Write-Host ""
}

function HtmlEncode([string]$s) {
    if ($null -eq $s) { return "" }
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

$AuthStrength = @{
    'open' = 'Insecure'; 'shared' = 'Insecure'; 'WEP' = 'Insecure'
    'WPA' = 'Weak'; 'WPAPSK' = 'Weak'
    'WPA2' = 'Strong'; 'WPA2PSK' = 'Strong'
    'WPA3' = 'Strong'; 'WPA3SAE' = 'Strong'; 'WPA3ENT' = 'Strong'; 'WPA3ENT192' = 'Strong'
    'OWE' = 'Strong'
}
$CipherStrength = @{ 'none' = 'Insecure'; 'WEP' = 'Insecure'; 'TKIP' = 'Weak'; 'AES' = 'Strong'; 'GCMP' = 'Strong' }

function Get-AuthTier([string]$Auth) {
    if ([string]::IsNullOrWhiteSpace($Auth)) { return 'Unknown' }
    if ($AuthStrength.ContainsKey($Auth)) { return $AuthStrength[$Auth] }
    'Unknown'
}
function Get-CipherTier([string]$C) {
    if ([string]::IsNullOrWhiteSpace($C)) { return 'Unknown' }
    if ($CipherStrength.ContainsKey($C)) { return $CipherStrength[$C] }
    'Unknown'
}
function Test-IsOpenProfile($P) {
    $a = "$($P.Authentication)".ToLower()
    return ($a -eq 'open' -and ("$($P.Encryption)".ToLower() -in @('none','')))
}
function Test-IsWeakProfile($P) {
    if (Test-IsOpenProfile $P) { return $true }
    if ((Get-AuthTier $P.Authentication) -eq 'Insecure') { return $true }
    if ((Get-CipherTier $P.Encryption) -eq 'Insecure')   { return $true }
    if ((Get-AuthTier $P.Authentication) -eq 'Weak')     { return $true }
    if ((Get-CipherTier $P.Encryption) -eq 'Weak')       { return $true }
    return $false
}

# ===========================
# COLLECTORS
# ===========================

function Get-WifiAdapters {
    try {
        $rows = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
            $_.PhysicalMediaType -eq 'Native 802.11' -or $_.MediaType -eq '802.11'
        } | ForEach-Object {
            [PSCustomObject]@{
                Name                 = $_.Name
                InterfaceDescription = $_.InterfaceDescription
                Status               = "$($_.Status)"
                LinkSpeed            = $_.LinkSpeed
                MacAddress           = $_.MacAddress
                DriverVersion        = $_.DriverVersion
                DriverDate           = $_.DriverDate
            }
        }
        return @($rows)
    } catch { return @() }
}

function Get-WlanProfileList {
    $raw = & netsh wlan show profiles 2>$null
    if (-not $raw) { return @() }
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in $raw) {
        if ($line -match '^\s+[^:]+:\s+(.+?)\s*$') {
            $cand = $matches[1].Trim()
            if ($cand -and $cand -notmatch '^(Hosted network|Group policy|User|All User|Granted Permission|Restrictions)') {
                $names.Add($cand)
            }
        }
    }
    return @($names | Select-Object -Unique)
}

function ConvertFrom-WlanProfileXml([string]$XmlPath) {
    try { [xml]$doc = Get-Content -Path $XmlPath -Raw -ErrorAction Stop } catch { return $null }
    $profile = $doc.WLANProfile
    if (-not $profile) { return $null }

    $ssidName = $null; $ssidHex = $null; $nonBroadcast = $false
    if ($profile.SSIDConfig -and $profile.SSIDConfig.SSID) {
        $ssidName = $profile.SSIDConfig.SSID.name
        $ssidHex  = $profile.SSIDConfig.SSID.hex
    }
    if ($profile.SSIDConfig -and $profile.SSIDConfig.nonBroadcast) {
        $nonBroadcast = ($profile.SSIDConfig.nonBroadcast -eq 'true')
    }

    $auth = $null; $encryption = $null; $useOneX = $false
    $keyType = $null; $keyProtected = $null; $keyMaterial = $null
    if ($profile.MSM -and $profile.MSM.security) {
        $sec = $profile.MSM.security
        if ($sec.authEncryption) {
            $auth       = $sec.authEncryption.authentication
            $encryption = $sec.authEncryption.encryption
            $useOneX    = ($sec.authEncryption.useOneX -eq 'true')
        }
        if ($sec.sharedKey) {
            $keyType      = $sec.sharedKey.keyType
            $keyProtected = ($sec.sharedKey.protected -eq 'true')
            $keyMaterial  = $sec.sharedKey.keyMaterial
        }
    }

    $macRand = $null
    if ($profile.MacRandomization) { $macRand = ($profile.MacRandomization.enableRandomization -eq 'true') }

    return [PSCustomObject]@{
        Name             = $profile.name
        SsidName         = $ssidName
        SsidHex          = $ssidHex
        NonBroadcast     = $nonBroadcast
        ConnectionType   = $profile.connectionType
        ConnectionMode   = $profile.connectionMode
        AutoSwitch       = ($profile.autoSwitch -eq 'true')
        Authentication   = $auth
        Encryption       = $encryption
        UseOneX          = $useOneX
        KeyType          = $keyType
        KeyProtected     = $keyProtected
        KeyMaterial      = $keyMaterial
        MacRandomization = $macRand
    }
}

function Get-WlanProfiles {
    $names = Get-WlanProfileList
    if ($names.Count -eq 0) { return @() }
    $rootTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("TK-SIGNAL-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $rootTemp -Force -ErrorAction SilentlyContinue

    $rows = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($n in $names) {
            $sub = Join-Path $rootTemp ([guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $sub -Force -ErrorAction SilentlyContinue
            $null = & netsh wlan export profile name="$n" folder="$sub" key=clear 2>&1
            $xml = Get-ChildItem -Path $sub -Filter '*.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $xml) { continue }
            $row = ConvertFrom-WlanProfileXml -XmlPath $xml.FullName
            if ($row) { $rows.Add($row) }
        }
    } finally {
        Remove-Item -Path $rootTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
    return @($rows)
}

# ===========================
# VERDICT
# ===========================

function Get-SignalVerdict {
    param([array]$Adapters, [array]$Profiles)
    $issues = @(); $warns = @()
    if ($Adapters.Count -eq 0) {
        $warns += 'No Wi-Fi adapter present on this machine -- desktop / wired-only configuration.'
    }
    foreach ($p in $Profiles) {
        $auth = "$($p.Authentication)"; $cipher = "$($p.Encryption)"
        $auto = ($p.ConnectionMode -eq 'auto')
        if (Test-IsOpenProfile $p) {
            if ($auto) { $issues += "Open profile '$($p.Name)' is set to AUTO-CONNECT -- this machine will silently associate to any AP advertising that SSID." }
            else       { $warns  += "Open profile '$($p.Name)' is configured (manual-connect)." }
        }
        if ((Get-CipherTier $cipher) -eq 'Insecure' -and $cipher -ne 'none') {
            $issues += "Profile '$($p.Name)' uses deprecated $cipher encryption -- WEP is broken; remove the profile."
        }
        if ((Get-AuthTier $auth)   -eq 'Weak') { $warns += "Profile '$($p.Name)' uses legacy $auth -- upgrade the network to WPA2-PSK / WPA3-SAE." }
        if ((Get-CipherTier $cipher) -eq 'Weak') { $warns += "Profile '$($p.Name)' uses TKIP cipher -- upgrade to AES (CCMP) or GCMP." }
        if ($p.AutoSwitch -and $auto) { $warns += "Profile '$($p.Name)' has autoSwitch enabled -- machine may roam between this and other known networks without prompt." }
        if ($p.NonBroadcast -and $auto) { $warns += "Hidden-SSID profile '$($p.Name)' is auto-connecting -- the client probes for it constantly, leaking the SSID." }
        if ($p.MacRandomization -eq $false) { $warns += "Profile '$($p.Name)' has MAC randomization disabled." }
    }
    if ($Profiles.Count -gt 25) {
        $warns += "$($Profiles.Count) saved Wi-Fi profiles -- a large profile estate increases roaming surprises. Consider periodic cleanup."
    }
    $verdict = if ($issues.Count -gt 0) { 'AT RISK' } elseif ($warns.Count -gt 0) { 'ATTENTION NEEDED' } else { 'CLEAN' }
    $class   = if ($issues.Count -gt 0) { 'crit' }   elseif ($warns.Count -gt 0) { 'warn' }             else { 'ok' }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Detecting Wi-Fi adapters..." -ForegroundColor Magenta
$adapters = Get-WifiAdapters
if ($adapters.Count -eq 0) {
    Write-Host "  No Wi-Fi adapters detected (desktop or wired-only configuration)." -ForegroundColor Gray
} else {
    foreach ($a in $adapters) {
        $color = if ($a.Status -eq 'Up') { 'Green' } else { 'Yellow' }
        Write-Host ("  {0,-14} {1,-8} {2}" -f $a.Name, $a.Status, $a.InterfaceDescription) -ForegroundColor $color
    }
}
Write-Host ""

Write-Host "[*] Exporting WLAN profiles and parsing..." -ForegroundColor Magenta
$profiles = Get-WlanProfiles
Write-Host ("  Profiles parsed      : {0}" -f $profiles.Count) -ForegroundColor Gray
$openCount = @($profiles | Where-Object { Test-IsOpenProfile $_ }).Count
$weakCount = @($profiles | Where-Object { Test-IsWeakProfile $_ }).Count
$autoCount = @($profiles | Where-Object { $_.ConnectionMode -eq 'auto' }).Count
Write-Host ("  Open profiles        : {0}" -f $openCount) -ForegroundColor $(if ($openCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ("  Open / weak profiles : {0}" -f $weakCount) -ForegroundColor $(if ($weakCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("  Auto-connect         : {0}" -f $autoCount) -ForegroundColor Gray
Write-Host ""

$verdict = Get-SignalVerdict -Adapters $adapters -Profiles $profiles
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WI-FI VERDICT" -ForegroundColor Cyan
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

function TierBadge([string]$Tier) {
    switch ($Tier) {
        'Strong'   { "<span class='badge badge-ok'>$(HtmlEncode $Tier)</span>" }
        'Weak'     { "<span class='badge badge-warn'>$(HtmlEncode $Tier)</span>" }
        'Insecure' { "<span class='badge badge-crit'>$(HtmlEncode $Tier)</span>" }
        default    { "<span class='badge badge-neutral'>$(HtmlEncode $Tier)</span>" }
    }
}
function YnBadge($b) { if ($b) { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-neutral'>No</span>" } }
function YnWarn($b)  { if ($b) { "<span class='badge badge-warn'>Yes</span>" } else { "<span class='badge badge-ok'>No</span>" } }
function KeyCell($P) {
    if ([string]::IsNullOrEmpty($P.KeyMaterial)) { return "<span class='badge badge-neutral'>None / enterprise</span>" }
    if ($IncludeKey) { return "<code>$(HtmlEncode $P.KeyMaterial)</code>" }
    return "<span class='badge badge-warn'>masked (use -IncludeKey to show)</span>"
}

$adRows = ""
if ($adapters.Count -eq 0) {
    $adRows = "<tr><td colspan='6' style='text-align:center;color:#aaa;'>No Wi-Fi adapters detected.</td></tr>"
} else {
    foreach ($a in $adapters) {
        $statBadge = if ($a.Status -eq 'Up') { "<span class='badge badge-ok'>Up</span>" } else { "<span class='badge badge-warn'>$(HtmlEncode $a.Status)</span>" }
        $adRows += "<tr><td>$(HtmlEncode $a.Name)</td><td>$(HtmlEncode $a.InterfaceDescription)</td><td>$statBadge</td><td>$(HtmlEncode $a.LinkSpeed)</td><td><code>$(HtmlEncode $a.MacAddress)</code></td><td>$(HtmlEncode $a.DriverVersion) ($(HtmlEncode "$($a.DriverDate)"))</td></tr>"
    }
}

$pRows = ""
if ($profiles.Count -eq 0) {
    $pRows = "<tr><td colspan='9' style='text-align:center;color:#aaa;'>No saved Wi-Fi profiles found.</td></tr>"
} else {
    foreach ($p in ($profiles | Sort-Object Name)) {
        $authBadge   = TierBadge (Get-AuthTier $p.Authentication)
        $cipherBadge = TierBadge (Get-CipherTier $p.Encryption)
        $modeBadge   = if ($p.ConnectionMode -eq 'auto') { "<span class='badge badge-warn'>auto</span>" } else { "<span class='badge badge-neutral'>$(HtmlEncode $p.ConnectionMode)</span>" }
        $macCell     = if ($null -eq $p.MacRandomization) { "<span class='badge badge-neutral'>n/a</span>" } else { YnBadge $p.MacRandomization }
        $pRows += "<tr><td><strong>$(HtmlEncode $p.Name)</strong></td><td>$(HtmlEncode $p.Authentication) $authBadge</td><td>$(HtmlEncode $p.Encryption) $cipherBadge</td><td>$modeBadge</td><td>$(YnWarn $p.AutoSwitch)</td><td>$(YnWarn $p.NonBroadcast)</td><td>$macCell</td><td>$(YnBadge $p.UseOneX)</td><td>$(KeyCell $p)</td></tr>"
    }
}

$weak = @($profiles | Where-Object { Test-IsWeakProfile $_ })
$weakRows = ""
if ($weak.Count -eq 0) {
    $weakRows = "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No open or weak-cipher profiles detected.</td></tr>"
} else {
    foreach ($p in $weak | Sort-Object Name) {
        $reasons = @()
        if (Test-IsOpenProfile $p)                                                                                  { $reasons += 'open authentication' }
        if ((Get-AuthTier $p.Authentication)   -eq 'Insecure' -and "$($p.Authentication)".ToLower() -ne 'open')     { $reasons += "insecure auth $($p.Authentication)" }
        if ((Get-AuthTier $p.Authentication)   -eq 'Weak')                                                          { $reasons += "weak auth $($p.Authentication)" }
        if ((Get-CipherTier $p.Encryption)     -eq 'Insecure')                                                      { $reasons += "insecure cipher $($p.Encryption)" }
        if ((Get-CipherTier $p.Encryption)     -eq 'Weak')                                                          { $reasons += "weak cipher $($p.Encryption)" }
        $weakRows += "<tr><td>$(HtmlEncode $p.Name)</td><td>$(HtmlEncode $p.Authentication)</td><td>$(HtmlEncode $p.Encryption)</td><td>$(HtmlEncode ($reasons -join ', '))</td></tr>"
    }
}

$auto = @($profiles | Where-Object { $_.ConnectionMode -eq 'auto' })
$autoRows = ""
if ($auto.Count -eq 0) {
    $autoRows = "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No auto-connect profiles configured.</td></tr>"
} else {
    foreach ($p in $auto | Sort-Object Name) {
        $cls = if (Test-IsOpenProfile $p) { 'badge-crit' } elseif (Test-IsWeakProfile $p) { 'badge-warn' } else { 'badge-neutral' }
        $tag = if (Test-IsOpenProfile $p) { 'open auto-connect' } elseif (Test-IsWeakProfile $p) { 'weak auto-connect' } else { 'auto-connect' }
        $autoRows += "<tr><td>$(HtmlEncode $p.Name)</td><td>$(HtmlEncode $p.Authentication)</td><td>$(HtmlEncode $p.Encryption)</td><td><span class='badge $cls'>$tag</span></td></tr>"
    }
}

$findingsList = ""
foreach ($i in $verdict.Issues) { $findingsList += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $findingsList += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $findingsList = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>No insecure or surprising Wi-Fi profiles found.</li>"
}

$strongCount = @($profiles | Where-Object { (Get-AuthTier $_.Authentication) -eq 'Strong' -and (Get-CipherTier $_.Encryption) -eq 'Strong' }).Count
$keyNote = if ($IncludeKey) { "<span class='badge badge-warn'>Key material rendered in cleartext (-IncludeKey)</span>" } else { "<span class='badge badge-ok'>Key material masked (default)</span>" }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>S.I.G.N.A.L. Wi-Fi -- $env:COMPUTERNAME</title>
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
  ul { list-style: none; padding-left: 0; }
  .footer { margin-top: 32px; color: #555; font-size: 11px; }
</style>
</head>
<body>
<h1>S.I.G.N.A.L. -- Wi-Fi Profile Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Wi-Fi Posture</div></div>
  <div class="card"><div class="val">$($adapters.Count)</div><div class="lbl">Wi-Fi Adapter(s)</div></div>
  <div class="card"><div class="val">$($profiles.Count)</div><div class="lbl">Saved Profiles</div></div>
  <div class="card $(if ($weak.Count -gt 0) { 'crit' } else { 'ok' })"><div class="val">$($weak.Count)</div><div class="lbl">Open / Weak</div></div>
  <div class="card $(if ($auto.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($auto.Count)</div><div class="lbl">Auto-connect</div></div>
  <div class="card ok"><div class="val">$strongCount</div><div class="lbl">Strong (WPA2/3 + AES)</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$findingsList</ul>
<div style="margin-top:8px;">$keyNote</div>

<div class="section-title">Wi-Fi Adapters ($($adapters.Count) detected)</div>
<table>
  <thead><tr><th>Name</th><th>Description</th><th>Status</th><th>Link</th><th>MAC</th><th>Driver</th></tr></thead>
  <tbody>$adRows</tbody>
</table>

<div class="section-title">Saved Profiles ($($profiles.Count) total)</div>
<table>
  <thead><tr><th>Profile</th><th>Authentication</th><th>Cipher</th><th>Connection</th><th>AutoSwitch</th><th>Hidden</th><th>MAC random</th><th>802.1X</th><th>Key</th></tr></thead>
  <tbody>$pRows</tbody>
</table>

<div class="section-title">Open / Weak Profiles ($($weak.Count) flagged)</div>
<table>
  <thead><tr><th>Profile</th><th>Authentication</th><th>Cipher</th><th>Reason</th></tr></thead>
  <tbody>$weakRows</tbody>
</table>

<div class="section-title">Auto-connecting Profiles ($($auto.Count) auto-connect)</div>
<table>
  <thead><tr><th>Profile</th><th>Authentication</th><th>Cipher</th><th>Risk Tier</th></tr></thead>
  <tbody>$autoRows</tbody>
</table>

<div class="footer">
  Generated by S.I.G.N.A.L. -- Technician Toolkit LiveConnect Suite
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
Write-Host "[OK] S.I.G.N.A.L. complete." -ForegroundColor Cyan
Write-Host ""
