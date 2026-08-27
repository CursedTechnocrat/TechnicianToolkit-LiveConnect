# tunnel.ps1 - T.U.N.N.E.L. — Tracks Unattended Network Negotiation Endpoints & Logging
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
    T.U.N.N.E.L. — Tracks Unattended Network Negotiation Endpoints & Logging
    LiveConnect-Compatible VPN / Always-On VPN Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Audits the VPN posture of a Windows endpoint. Enumerates built-in
    Windows VPN connections at user and all-user scope, surfaces Always-On
    VPN app & DNS triggers, dumps the Name Resolution Policy Table (NRPT),
    lists VPN tunnel interfaces, and detects installed third-party VPN
    clients via the service table (Cisco AnyConnect / Secure Client, Palo
    Alto GlobalProtect, Ivanti / Pulse, OpenVPN, WireGuard, Tailscale,
    ZeroTier, Cloudflare WARP, NordVPN, ProtonVPN, F5, Citrix).

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    Read-only — no state-changing actions are performed.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\tunnel.ps1
    PS C:\> .\tunnel.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : P.O.R.T.A.L. (main toolkit)
#>

param([string]$ReportPath = "C:\Temp")

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$reportFilename = "TUNNEL_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  T.U.N.N.E.L. -- Tracks Unattended Network Negotiation Endpoints & Logging" -ForegroundColor Cyan
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

$AuthStrength = @{
    'Pap' = 'Insecure'; 'Chap' = 'Weak'; 'MSChapv2' = 'Acceptable'
    'Eap' = 'Strong'; 'MachineCertificate' = 'Strong'
}
$EncryptionStrength = @{
    'NoEncryption' = 'Insecure'; 'Optional' = 'Weak'
    'Required'     = 'Strong';   'Maximum'  = 'Strong'
}

$ThirdPartyClients = @(
    @{ Pattern = 'vpnagent';                     Friendly = 'Cisco AnyConnect / Secure Client'; Vendor = 'Cisco' }
    @{ Pattern = 'csc_vpnagent';                 Friendly = 'Cisco Secure Client (newer)';      Vendor = 'Cisco' }
    @{ Pattern = 'PanGPS';                       Friendly = 'GlobalProtect (service)';          Vendor = 'Palo Alto' }
    @{ Pattern = 'PanGPA';                       Friendly = 'GlobalProtect (agent)';            Vendor = 'Palo Alto' }
    @{ Pattern = 'JuniperNetworksTunnelService'; Friendly = 'Juniper / Pulse Tunnel';           Vendor = 'Ivanti' }
    @{ Pattern = 'PulseService';                 Friendly = 'Pulse Secure Service';             Vendor = 'Ivanti' }
    @{ Pattern = 'OpenVPNService';               Friendly = 'OpenVPN (interactive service)';    Vendor = 'OpenVPN' }
    @{ Pattern = 'OpenVPNServiceLegacy';         Friendly = 'OpenVPN (legacy)';                 Vendor = 'OpenVPN' }
    @{ Pattern = 'OpenVPNServiceInteractive';    Friendly = 'OpenVPN GUI';                      Vendor = 'OpenVPN' }
    @{ Pattern = 'WireGuardManager';             Friendly = 'WireGuard manager';                Vendor = 'WireGuard' }
    @{ Pattern = 'WireGuardTunnel*';             Friendly = 'WireGuard tunnel (per-config)';    Vendor = 'WireGuard' }
    @{ Pattern = 'Tailscale';                    Friendly = 'Tailscale';                        Vendor = 'Tailscale' }
    @{ Pattern = 'ZeroTierOneService';            Friendly = 'ZeroTier One';                    Vendor = 'ZeroTier' }
    @{ Pattern = 'CloudflareWARP';                Friendly = 'Cloudflare WARP';                 Vendor = 'Cloudflare' }
    @{ Pattern = 'nordvpn-service';              Friendly = 'NordVPN';                          Vendor = 'Nord Security' }
    @{ Pattern = 'ProtonVPNService';             Friendly = 'Proton VPN';                       Vendor = 'Proton AG' }
    @{ Pattern = 'F5 BIG-IP Edge Client';        Friendly = 'F5 BIG-IP Edge Client';            Vendor = 'F5' }
    @{ Pattern = 'CitrixWorkspaceUpdater';        Friendly = 'Citrix Workspace (heuristic)';    Vendor = 'Citrix' }
)

function VpnRowFromCmdlet($V, [string]$Scope) {
    $authArr = @()
    if ($V.AuthenticationMethod) { $authArr = @($V.AuthenticationMethod | ForEach-Object { "$_" }) }
    return [PSCustomObject]@{
        Name                  = $V.Name
        Scope                 = $Scope
        ServerAddress         = $V.ServerAddress
        TunnelType            = "$($V.TunnelType)"
        AuthMethods           = $authArr
        AuthMethodsDisplay    = ($authArr -join ', ')
        EncryptionLevel       = "$($V.EncryptionLevel)"
        UseWinlogonCredential = [bool]$V.UseWinlogonCredential
        ConnectionStatus      = "$($V.ConnectionStatus)"
        RememberCredential    = [bool]$V.RememberCredential
        SplitTunneling        = [bool]$V.SplitTunneling
        DnsSuffix             = $V.DnsSuffix
        IdleDisconnectSeconds = $V.IdleDisconnectSeconds
        ProfileType           = "$($V.ProfileType)"
    }
}

function Get-VpnConnections {
    $rows = @()
    try { foreach ($v in @(Get-VpnConnection -ErrorAction Stop))                  { $rows += VpnRowFromCmdlet -V $v -Scope 'User' } }    catch {}
    try { foreach ($v in @(Get-VpnConnection -AllUserConnection -ErrorAction Stop)) { $rows += VpnRowFromCmdlet -V $v -Scope 'AllUser' } } catch {}
    return @($rows)
}

function Get-AlwaysOnTriggers {
    param([array]$Connections)
    $rows = @()
    foreach ($c in $Connections) {
        try {
            $params = @{ ConnectionName = $c.Name; ErrorAction = 'Stop' }
            if ($c.Scope -eq 'AllUser') { $params.AllUserConnection = $true }
            $trigger = Get-VpnConnectionTrigger @params
            if (-not $trigger) { continue }

            $apps = @(); if ($trigger.ApplicationID) { $apps = @($trigger.ApplicationID | Where-Object { $_ }) }
            $dns  = @()
            if ($trigger.DnsConfiguration) {
                $dns = @($trigger.DnsConfiguration | ForEach-Object { "$($_.DnsSuffix) -> $(($_.DnsServers -join ', '))" })
            }
            if ($apps.Count -gt 0 -or $dns.Count -gt 0) {
                $rows += [PSCustomObject]@{
                    ConnectionName = $c.Name; Scope = $c.Scope; Apps = $apps; DnsRules = $dns
                }
            }
        } catch { continue }
    }
    return @($rows)
}

function Get-NrptEntries {
    try { $rules = @(Get-DnsClientNrptPolicy -ErrorAction Stop) }
    catch { return @() }
    return @($rules | ForEach-Object {
        [PSCustomObject]@{
            Namespace           = (@($_.Namespace) -join ', ')
            DnsServers          = (@($_.NameServers) -join ', ')
            DirectAccessServers = (@($_.DirectAccessDnsServers) -join ', ')
            IpsecRequired       = [bool]$_.IPsecRequired
            EncryptionType      = "$($_.DnsSecValidationRequired)"
            Comment             = $_.Comment
        }
    })
}

function Get-VpnTunnelInterfaces {
    try {
        $ifaces = @(Get-NetIPInterface -ErrorAction Stop | Where-Object {
            $_.ConnectionState -eq 'Connected' -and (
                $_.InterfaceAlias -match 'VPN|Wintun|WireGuard|Tailscale|GlobalProtect|AnyConnect|PPP'
            )
        })
    } catch { return @() }
    return @($ifaces | ForEach-Object {
        [PSCustomObject]@{
            InterfaceAlias  = $_.InterfaceAlias
            AddressFamily   = "$($_.AddressFamily)"
            ConnectionState = "$($_.ConnectionState)"
            Forwarding      = "$($_.Forwarding)"
            Dhcp            = "$($_.Dhcp)"
            InterfaceMetric = $_.InterfaceMetric
        }
    })
}

function Get-ThirdPartyVpnClients {
    $rows = @()
    foreach ($entry in $ThirdPartyClients) {
        try { $svcs = @(Get-Service -Name $entry.Pattern -ErrorAction SilentlyContinue) } catch { $svcs = @() }
        foreach ($s in $svcs) {
            $rows += [PSCustomObject]@{
                Name = $s.Name; Friendly = $entry.Friendly; Vendor = $entry.Vendor
                Status = "$($s.Status)"; StartType = "$($s.StartType)"
            }
        }
    }
    return @($rows)
}

function Get-VpnAuthTier([array]$Methods) {
    if (-not $Methods -or $Methods.Count -eq 0) { return 'Unknown' }
    $tier = 'Strong'
    foreach ($m in $Methods) {
        $t = if ($AuthStrength.ContainsKey("$m")) { $AuthStrength["$m"] } else { 'Unknown' }
        switch ($t) {
            'Insecure'   { return 'Insecure' }
            'Weak'       { if ($tier -ne 'Insecure') { $tier = 'Weak' } }
            'Acceptable' { if ($tier -eq 'Strong')   { $tier = 'Acceptable' } }
            'Unknown'    { if ($tier -eq 'Strong')   { $tier = 'Unknown' } }
        }
    }
    return $tier
}
function Get-VpnEncryptionTier([string]$Level) {
    if ($EncryptionStrength.ContainsKey($Level)) { return $EncryptionStrength[$Level] }
    'Unknown'
}

function Get-TunnelVerdict {
    param([array]$Vpns, [array]$Triggers, [array]$Nrpt, [array]$ThirdParty)
    $issues = @(); $warns = @()
    if ($Vpns.Count -eq 0 -and $ThirdParty.Count -eq 0) {
        return [PSCustomObject]@{
            Verdict = 'NONE CONFIGURED'; Class = 'neutral'; Issues = @()
            Warns = @('No built-in Windows VPN connections and no third-party VPN clients detected.')
        }
    }
    foreach ($v in $Vpns) {
        $authTier = Get-VpnAuthTier -Methods $v.AuthMethods
        $encTier  = Get-VpnEncryptionTier -Level $v.EncryptionLevel
        if ($authTier -eq 'Insecure') { $issues += "VPN '$($v.Name)' accepts PAP authentication -- credentials transmitted in cleartext." }
        elseif ($authTier -eq 'Weak') { $warns  += "VPN '$($v.Name)' accepts CHAP -- deprecated; require MS-CHAPv2 or EAP." }
        if ($encTier -eq 'Insecure')  { $issues += "VPN '$($v.Name)' uses NoEncryption -- traffic flows in the clear over the tunnel." }
        elseif ($encTier -eq 'Weak')  { $warns  += "VPN '$($v.Name)' has Optional encryption -- raise to Required or Maximum." }
        if ($v.SplitTunneling) {
            $hasNrpt = @($Nrpt | Where-Object { $_.Namespace -and $v.DnsSuffix -and ($_.Namespace -match [regex]::Escape($v.DnsSuffix)) }).Count -gt 0
            if (-not $hasNrpt) {
                $warns += "VPN '$($v.Name)' is split-tunnel with no NRPT entry covering its DNS suffix '$($v.DnsSuffix)' -- internal-name resolution may leak."
            }
        }
        if ($v.Scope -eq 'AllUser' -and $v.ConnectionStatus -eq 'Disconnected') {
            $warns += "All-user VPN '$($v.Name)' is currently Disconnected -- expected if Always-On has not triggered yet."
        }
    }
    $vendors = @($ThirdParty | Select-Object -ExpandProperty Vendor -Unique)
    if ($vendors.Count -gt 1) {
        $warns += "$($vendors.Count) different VPN vendors detected on this machine ($([string]::Join(', ', $vendors))) -- competing route tables can produce intermittent connectivity."
    }
    $verdict = if ($issues.Count -gt 0) { 'AT RISK' } elseif ($warns.Count -gt 0) { 'ATTENTION NEEDED' } else { 'OK' }
    $class   = if ($issues.Count -gt 0) { 'crit' }   elseif ($warns.Count -gt 0) { 'warn' }             else { 'ok' }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Built-in VPN connections..." -ForegroundColor Magenta
$vpns = Get-VpnConnections
Write-Host ("  Built-in VPN connections  : {0}" -f $vpns.Count) -ForegroundColor Gray
foreach ($v in $vpns) {
    $authTier = Get-VpnAuthTier -Methods $v.AuthMethods
    $encTier  = Get-VpnEncryptionTier -Level $v.EncryptionLevel
    $color = if ($authTier -eq 'Insecure' -or $encTier -eq 'Insecure') { 'Red' }
             elseif ($authTier -in @('Weak','Acceptable') -or $encTier -eq 'Weak') { 'Yellow' }
             else { 'Green' }
    Write-Host ("  - {0,-25} [{1}] auth={2} enc={3} state={4}" -f $v.Name, $v.Scope, $v.AuthMethodsDisplay, $v.EncryptionLevel, $v.ConnectionStatus) -ForegroundColor $color
}
Write-Host ""

Write-Host "[*] Always-On triggers..." -ForegroundColor Magenta
$triggers = Get-AlwaysOnTriggers -Connections $vpns
Write-Host ("  App/DNS-trigger entries   : {0}" -f $triggers.Count) -ForegroundColor Gray

Write-Host "[*] NRPT rules..." -ForegroundColor Magenta
$nrpt = Get-NrptEntries
Write-Host ("  NRPT rules                : {0}" -f $nrpt.Count) -ForegroundColor Gray

Write-Host "[*] Active tunnel interfaces..." -ForegroundColor Magenta
$tunnels = Get-VpnTunnelInterfaces
Write-Host ("  Connected tunnel ifaces   : {0}" -f $tunnels.Count) -ForegroundColor Gray

Write-Host "[*] Third-party VPN clients..." -ForegroundColor Magenta
$thirdParty = Get-ThirdPartyVpnClients
Write-Host ("  Detected client services  : {0}" -f $thirdParty.Count) -ForegroundColor Gray
foreach ($c in $thirdParty) {
    $color = if ($c.Status -eq 'Running') { 'Green' } else { 'Gray' }
    Write-Host ("    - {0,-30} ({1})  service: {2,-30} {3}" -f $c.Friendly, $c.Vendor, $c.Name, $c.Status) -ForegroundColor $color
}
Write-Host ""

$verdict = Get-TunnelVerdict -Vpns $vpns -Triggers $triggers -Nrpt $nrpt -ThirdParty $thirdParty
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VPN VERDICT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$vColor = switch ($verdict.Class) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'crit' { 'Red' } default { 'Gray' } }
Write-Host "  $($verdict.Verdict)" -ForegroundColor $vColor
foreach ($i in $verdict.Issues) { Write-Host "    [!!] $i" -ForegroundColor Red }
foreach ($w in $verdict.Warns)  { Write-Host "    [~ ] $w" -ForegroundColor Yellow }
if ($verdict.Class -eq 'ok' -and $verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    Write-Host "    [+ ] All checks passed." -ForegroundColor Green
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

function TierBadge([string]$T) {
    switch ($T) {
        'Strong'     { "<span class='badge badge-ok'>$(HtmlEncode $T)</span>" }
        'Acceptable' { "<span class='badge badge-neutral'>$(HtmlEncode $T)</span>" }
        'Weak'       { "<span class='badge badge-warn'>$(HtmlEncode $T)</span>" }
        'Insecure'   { "<span class='badge badge-crit'>$(HtmlEncode $T)</span>" }
        default      { "<span class='badge badge-neutral'>$(HtmlEncode $T)</span>" }
    }
}
function YnWarn($b) { if ($b) { "<span class='badge badge-warn'>Yes</span>" } else { "<span class='badge badge-ok'>No</span>" } }

$vRows = ""
if ($vpns.Count -eq 0) {
    $vRows = "<tr><td colspan='9' style='text-align:center;color:#aaa;'>No built-in Windows VPN connections configured.</td></tr>"
} else {
    foreach ($v in $vpns | Sort-Object Scope, Name) {
        $authTier = Get-VpnAuthTier -Methods $v.AuthMethods
        $encTier  = Get-VpnEncryptionTier -Level $v.EncryptionLevel
        $stateBadge = switch ($v.ConnectionStatus) {
            'Connected'    { "<span class='badge badge-ok'>Connected</span>" }
            'Disconnected' { "<span class='badge badge-neutral'>Disconnected</span>" }
            default        { "<span class='badge badge-warn'>$(HtmlEncode $v.ConnectionStatus)</span>" }
        }
        $vRows += "<tr><td><strong>$(HtmlEncode $v.Name)</strong></td><td>$(HtmlEncode $v.Scope)</td><td><code>$(HtmlEncode $v.ServerAddress)</code></td><td>$(HtmlEncode $v.TunnelType)</td><td>$(HtmlEncode $v.AuthMethodsDisplay) $(TierBadge $authTier)</td><td>$(HtmlEncode $v.EncryptionLevel) $(TierBadge $encTier)</td><td>$(YnWarn $v.SplitTunneling)</td><td>$stateBadge</td><td>$(HtmlEncode $v.ProfileType)</td></tr>"
    }
}

$tRows = ""
if ($triggers.Count -eq 0) {
    $tRows = "<tr><td colspan='4' style='text-align:center;color:#aaa;'>No app-triggered Always-On entries configured.</td></tr>"
} else {
    foreach ($t in $triggers) {
        $appList = if ($t.Apps.Count -gt 0) { ($t.Apps | ForEach-Object { "<code>$(HtmlEncode $_)</code>" }) -join '<br/>' } else { '<span class="badge badge-neutral">none</span>' }
        $dnsList = if ($t.DnsRules.Count -gt 0) { ($t.DnsRules | ForEach-Object { "<code>$(HtmlEncode $_)</code>" }) -join '<br/>' } else { '<span class="badge badge-neutral">none</span>' }
        $tRows += "<tr><td>$(HtmlEncode $t.ConnectionName)</td><td>$(HtmlEncode $t.Scope)</td><td>$appList</td><td>$dnsList</td></tr>"
    }
}

$nRows = ""
if ($nrpt.Count -eq 0) {
    $nRows = "<tr><td colspan='5' style='text-align:center;color:#aaa;'>No NRPT rules configured.</td></tr>"
} else {
    foreach ($n in $nrpt) {
        $nRows += "<tr><td><code>$(HtmlEncode $n.Namespace)</code></td><td><code>$(HtmlEncode $n.DnsServers)</code></td><td><code>$(HtmlEncode $n.DirectAccessServers)</code></td><td>$(YnWarn $n.IpsecRequired)</td><td>$(HtmlEncode $n.Comment)</td></tr>"
    }
}

$iRows = ""
if ($tunnels.Count -eq 0) {
    $iRows = "<tr><td colspan='5' style='text-align:center;color:#aaa;'>No active VPN tunnel interfaces detected.</td></tr>"
} else {
    foreach ($i in $tunnels) {
        $iRows += "<tr><td>$(HtmlEncode $i.InterfaceAlias)</td><td>$(HtmlEncode $i.AddressFamily)</td><td>$(HtmlEncode $i.ConnectionState)</td><td>$(HtmlEncode "$($i.Dhcp)")</td><td>$(HtmlEncode "$($i.InterfaceMetric)")</td></tr>"
    }
}

$cRows = ""
if ($thirdParty.Count -eq 0) {
    $cRows = "<tr><td colspan='5' style='text-align:center;color:#aaa;'>No third-party VPN clients detected.</td></tr>"
} else {
    foreach ($c in $thirdParty) {
        $statusBadge = if ($c.Status -eq 'Running') { "<span class='badge badge-ok'>Running</span>" } else { "<span class='badge badge-neutral'>$(HtmlEncode $c.Status)</span>" }
        $cRows += "<tr><td>$(HtmlEncode $c.Friendly)</td><td>$(HtmlEncode $c.Vendor)</td><td><code>$(HtmlEncode $c.Name)</code></td><td>$statusBadge</td><td>$(HtmlEncode $c.StartType)</td></tr>"
    }
}

$findingsList = ""
foreach ($i in $verdict.Issues) { $findingsList += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $findingsList += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $findingsList = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>No insecure VPN configurations detected.</li>"
}

$allUserCount = @($vpns | Where-Object { $_.Scope -eq 'AllUser' }).Count
$userCount    = @($vpns | Where-Object { $_.Scope -eq 'User' }).Count

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>T.U.N.N.E.L. VPN -- $env:COMPUTERNAME</title>
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
  .card.neutral .val { color: #aaa; }
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
<h1>T.U.N.N.E.L. -- VPN / Always-On VPN Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">VPN Posture</div></div>
  <div class="card"><div class="val">$($vpns.Count)</div><div class="lbl">Built-in VPNs</div></div>
  <div class="card"><div class="val">$allUserCount</div><div class="lbl">All-user (AOVPN candidate)</div></div>
  <div class="card"><div class="val">$($triggers.Count)</div><div class="lbl">App Triggers</div></div>
  <div class="card"><div class="val">$($nrpt.Count)</div><div class="lbl">NRPT Entries</div></div>
  <div class="card $(if ($thirdParty.Count -gt 0) { 'warn' } else { 'ok' })"><div class="val">$($thirdParty.Count)</div><div class="lbl">Third-Party Clients</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$findingsList</ul>

<div class="section-title">Built-in Windows VPN Connections ($userCount user / $allUserCount all-user)</div>
<table>
  <thead><tr><th>Name</th><th>Scope</th><th>Server</th><th>Tunnel</th><th>Auth</th><th>Encryption</th><th>Split-Tunnel</th><th>State</th><th>Profile</th></tr></thead>
  <tbody>$vRows</tbody>
</table>

<div class="section-title">Always-On VPN Triggers ($($triggers.Count) configured)</div>
<table>
  <thead><tr><th>Connection</th><th>Scope</th><th>Triggering Apps</th><th>DNS Triggers</th></tr></thead>
  <tbody>$tRows</tbody>
</table>

<div class="section-title">NRPT Entries ($($nrpt.Count) rules)</div>
<table>
  <thead><tr><th>Namespace</th><th>DNS Servers</th><th>DirectAccess Servers</th><th>IPsec required</th><th>Comment</th></tr></thead>
  <tbody>$nRows</tbody>
</table>

<div class="section-title">VPN Tunnel Interfaces ($($tunnels.Count) connected)</div>
<table>
  <thead><tr><th>Interface</th><th>Family</th><th>State</th><th>DHCP</th><th>Metric</th></tr></thead>
  <tbody>$iRows</tbody>
</table>

<div class="section-title">Third-Party VPN Clients ($($thirdParty.Count) detected)</div>
<table>
  <thead><tr><th>Product</th><th>Vendor</th><th>Service</th><th>Status</th><th>Start Type</th></tr></thead>
  <tbody>$cRows</tbody>
</table>

<div class="footer">
  Generated by T.U.N.N.E.L. -- Technician Toolkit LiveConnect Suite. Read-only audit.
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
Write-Host "[OK] T.U.N.N.E.L. complete." -ForegroundColor Cyan
Write-Host ""
