# aegis.ps1 - A.E.G.I.S. — Antivirus Endpoint Guard Inspection Snapshot
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
    A.E.G.I.S. — Antivirus Endpoint Guard Inspection Snapshot
    LiveConnect-Compatible AV / Microsoft Defender Health Audit for PowerShell 5.1+

.DESCRIPTION
    Audits the antivirus posture of a Windows endpoint. Reads Defender state
    via Get-MpComputerStatus / Get-MpPreference, threat history via
    Get-MpThreat / Get-MpThreatDetection, registered AV products via the
    SecurityCenter2 WMI namespace, AV service state, and recent Defender
    Operational events. Produces a dark-themed HTML report with a
    red / yellow / green verdict and per-section detail tables.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    Read-only audit — no state-changing actions are performed.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\aegis.ps1
    PS C:\> .\aegis.ps1 -ReportPath "C:\Temp"
    PS C:\> .\aegis.ps1 -EventDays 14 -SignatureMaxAgeDays 3

.PARAMETERS
    -ReportPath            Folder where the HTML report is saved (default: C:\Temp)
    -EventDays             Days of Defender Operational log to read (default: 7, max 90)
    -SignatureMaxAgeDays   Yellow threshold for signature age (default: 7, double = red)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : P.A.L.A.D.I.N. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp",
    [ValidateRange(1, 90)] [int]$EventDays = 7,
    [ValidateRange(1, 30)] [int]$SignatureMaxAgeDays = 7
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
$reportFilename = "AEGIS_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  A.E.G.I.S. -- Antivirus Endpoint Guard Inspection Snapshot" -ForegroundColor Cyan
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

function YnBadge([bool]$b) {
    if ($b) { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-crit'>No</span>" }
}
function YnWarnBadge([bool]$b) {
    if ($b) { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-warn'>No</span>" }
}
function AgeBadge {
    param($age, $maxOk, $maxWarn)
    if ($null -eq $age)        { return "<span class='badge badge-warn'>Unknown</span>" }
    if ($age -le $maxOk)       { return "<span class='badge badge-ok'>$age day(s)</span>" }
    if ($age -le $maxWarn)     { return "<span class='badge badge-warn'>$age day(s)</span>" }
    return "<span class='badge badge-crit'>$age day(s)</span>"
}

# ASR rule GUID -> friendly name
$AsrRuleNames = @{
    '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Block abuse of exploited vulnerable signed drivers'
    '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Block Adobe Reader from creating child processes'
    'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block Office apps from creating child processes'
    '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Block credential stealing from LSASS'
    'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email/webmail'
    '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executable files unless meeting prevalence/age/trusted criteria'
    '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
    'd3e037e1-3eb8-44c8-a917-57927947596d' = 'Block JavaScript/VBScript from launching downloaded content'
    '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office apps from creating executable content'
    '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office apps from injecting code into other processes'
    '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication apps from creating child processes'
    'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Block persistence through WMI event subscription'
    'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'Block process creations from PsExec and WMI commands'
    'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted/unsigned processes from USB'
    '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
    'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'Use advanced protection against ransomware'
    'a8f5898e-1dc8-49a9-9878-85004b8a61e6' = 'Block Webshell creation for Servers'
    '33ddedf1-c6e0-47cb-833e-de6133960387' = 'Block rebooting machine in Safe Mode (preview)'
    'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'Block use of copied or impersonated system tools (preview)'
}

function Get-AsrActionLabel {
    param([int]$Action)
    switch ($Action) { 0 {'Not Configured'} 1 {'Block'} 2 {'Audit'} 6 {'Warn'} default { "Unknown ($Action)" } }
}

$DefenderServices = @(
    @{ Name = 'WinDefend';            Friendly = 'Microsoft Defender Antivirus Service'; Critical = $true  }
    @{ Name = 'WdNisSvc';             Friendly = 'Defender Network Inspection';          Critical = $false }
    @{ Name = 'Sense';                Friendly = 'Defender for Endpoint (EDR)';          Critical = $false }
    @{ Name = 'WdFilter';             Friendly = 'Defender mini-filter driver';          Critical = $true  }
    @{ Name = 'SecurityHealthService'; Friendly = 'Windows Security UI host';            Critical = $false }
    @{ Name = 'mpssvc';               Friendly = 'Windows Defender Firewall';            Critical = $false }
)

# ===========================
# COLLECTORS
# ===========================

function Get-DefenderState {
    try { $s = Get-MpComputerStatus -ErrorAction Stop }
    catch { return [PSCustomObject]@{ CollectorError = $_.Exception.Message } }

    return [PSCustomObject]@{
        CollectorError                  = $null
        AMServiceEnabled                = [bool]$s.AMServiceEnabled
        AMRunningMode                   = "$($s.AMRunningMode)"
        AMEngineVersion                 = "$($s.AMEngineVersion)"
        AMServiceVersion                = "$($s.AMServiceVersion)"
        AMProductVersion                = "$($s.AMProductVersion)"
        AntivirusEnabled                = [bool]$s.AntivirusEnabled
        AntispywareEnabled              = [bool]$s.AntispywareEnabled
        RealTimeProtectionEnabled       = [bool]$s.RealTimeProtectionEnabled
        BehaviorMonitorEnabled          = [bool]$s.BehaviorMonitorEnabled
        IoavProtectionEnabled           = [bool]$s.IoavProtectionEnabled
        OnAccessProtectionEnabled       = [bool]$s.OnAccessProtectionEnabled
        NISEnabled                      = [bool]$s.NISEnabled
        TamperProtected                 = [bool]$s.TamperProtected
        IsTamperProtected               = [bool]$s.IsTamperProtected
        AntivirusSignatureVersion       = "$($s.AntivirusSignatureVersion)"
        AntivirusSignatureLastUpdated   = $s.AntivirusSignatureLastUpdated
        AntivirusSignatureAge           = $s.AntivirusSignatureAge
        AntispywareSignatureVersion     = "$($s.AntispywareSignatureVersion)"
        AntispywareSignatureLastUpdated = $s.AntispywareSignatureLastUpdated
        AntispywareSignatureAge         = $s.AntispywareSignatureAge
        NISSignatureVersion             = "$($s.NISSignatureVersion)"
        NISSignatureLastUpdated         = $s.NISSignatureLastUpdated
        NISSignatureAge                 = $s.NISSignatureAge
        QuickScanStartTime              = $s.QuickScanStartTime
        QuickScanEndTime                = $s.QuickScanEndTime
        QuickScanAge                    = $s.QuickScanAge
        FullScanStartTime               = $s.FullScanStartTime
        FullScanEndTime                 = $s.FullScanEndTime
        FullScanAge                     = $s.FullScanAge
    }
}

function Get-DefenderPreference {
    try { $p = Get-MpPreference -ErrorAction Stop }
    catch { return [PSCustomObject]@{ CollectorError = $_.Exception.Message } }

    $asr = @()
    if ($p.AttackSurfaceReductionRules_Ids -and $p.AttackSurfaceReductionRules_Actions) {
        $ids     = @($p.AttackSurfaceReductionRules_Ids)
        $actions = @($p.AttackSurfaceReductionRules_Actions)
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $id     = "$($ids[$i])".ToLower()
            $action = if ($i -lt $actions.Count) { [int]$actions[$i] } else { 0 }
            $asr += [PSCustomObject]@{
                Id     = $id
                Name   = if ($AsrRuleNames.ContainsKey($id)) { $AsrRuleNames[$id] } else { 'Unknown ASR rule' }
                Action = $action
                Label  = Get-AsrActionLabel -Action $action
            }
        }
    }

    return [PSCustomObject]@{
        CollectorError                = $null
        ExclusionPath                 = @($p.ExclusionPath      | Where-Object { $_ })
        ExclusionExtension            = @($p.ExclusionExtension | Where-Object { $_ })
        ExclusionProcess              = @($p.ExclusionProcess   | Where-Object { $_ })
        ExclusionIpAddress            = @($p.ExclusionIpAddress | Where-Object { $_ })
        AsrRules                      = @($asr)
        MAPSReporting                 = $p.MAPSReporting
        SubmitSamplesConsent          = $p.SubmitSamplesConsent
        CloudBlockLevel               = $p.CloudBlockLevel
        CloudExtendedTimeout          = $p.CloudExtendedTimeout
        DisableArchiveScanning        = [bool]$p.DisableArchiveScanning
        DisableEmailScanning          = [bool]$p.DisableEmailScanning
        DisableScriptScanning         = [bool]$p.DisableScriptScanning
        DisableRemovableDriveScanning = [bool]$p.DisableRemovableDriveScanning
        PUAProtection                 = $p.PUAProtection
        DisableRealtimeMonitoring     = [bool]$p.DisableRealtimeMonitoring
        DisableBehaviorMonitoring     = [bool]$p.DisableBehaviorMonitoring
        DisableIOAVProtection         = [bool]$p.DisableIOAVProtection
    }
}

function Get-ThreatHistorySnapshot {
    try { $threats = @(Get-MpThreat -ErrorAction Stop) }
    catch { return [PSCustomObject]@{ Threats = @(); UnresolvedHigh = 0 } }

    $unresolvedHigh = 0
    $rows = foreach ($t in $threats) {
        $sevName = switch ([int]$t.SeverityID) {
            1 { 'Low' } 2 { 'Moderate' } 4 { 'High' } 5 { 'Severe' } default { "Sev$($t.SeverityID)" }
        }
        $active = [bool]$t.IsActive
        if (([int]$t.SeverityID -ge 4) -and $active) { $unresolvedHigh++ }
        [PSCustomObject]@{
            ThreatID       = $t.ThreatID
            ThreatName     = $t.ThreatName
            Severity       = $sevName
            SeverityID     = [int]$t.SeverityID
            IsActive       = $active
            DetectionCount = $t.DetectionCount
            Resources      = (@($t.Resources) -join '; ')
        }
    }
    return [PSCustomObject]@{ Threats = @($rows); UnresolvedHigh = $unresolvedHigh }
}

function Get-RecentDetectionSnapshot {
    try { $detections = @(Get-MpThreatDetection -ErrorAction Stop) }
    catch { return [PSCustomObject]@{ Detections = @() } }

    $rows = foreach ($d in $detections | Sort-Object InitialDetectionTime -Descending | Select-Object -First 50) {
        [PSCustomObject]@{
            InitialDetectionTime = $d.InitialDetectionTime
            ProcessName          = $d.ProcessName
            DomainUser           = $d.DomainUser
            Resources            = (@($d.Resources) -join '; ')
            ActionSuccess        = $d.ActionSuccess
        }
    }
    return [PSCustomObject]@{ Detections = @($rows) }
}

function Get-ThirdPartyAvProducts {
    try { $items = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction Stop) }
    catch { return [PSCustomObject]@{ Available = $false; Products = @() } }

    $rows = foreach ($p in $items) {
        $state = [int]$p.productState
        $rt    = ($state -band 0x1000) -ne 0
        $up    = ($state -band 0x10)   -eq 0
        [PSCustomObject]@{
            DisplayName  = $p.displayName
            ProductState = ('0x{0:X}' -f $state)
            RealTimeOn   = $rt
            UpToDate     = $up
            ExePath      = $p.pathToSignedReportingExe
        }
    }
    return [PSCustomObject]@{ Available = $true; Products = @($rows) }
}

function Get-DefenderServiceStatus {
    $rows = foreach ($svc in $DefenderServices) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($null -eq $s) {
            [PSCustomObject]@{ Name = $svc.Name; Friendly = $svc.Friendly; Status = 'NotInstalled'; StartType = $null; Critical = $svc.Critical }
        } else {
            [PSCustomObject]@{ Name = $svc.Name; Friendly = $svc.Friendly; Status = "$($s.Status)"; StartType = "$($s.StartType)"; Critical = $svc.Critical }
        }
    }
    return @($rows)
}

function Get-DefenderEvents {
    param([int]$Days)
    $since = (Get-Date).AddDays(-$Days)
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-Windows Defender/Operational'
            StartTime = $since
        } -ErrorAction Stop | Select-Object -First 100
    } catch { return [PSCustomObject]@{ Available = $false; Events = @() } }

    $rows = foreach ($e in $events) {
        $msg = if ($e.Message) { ($e.Message -split "`r?`n")[0] } else { '' }
        [PSCustomObject]@{
            TimeCreated = $e.TimeCreated
            Id          = $e.Id
            Level       = "$($e.LevelDisplayName)"
            Message     = $msg
        }
    }
    return [PSCustomObject]@{ Available = $true; Events = @($rows) }
}

# ===========================
# VERDICT
# ===========================

function Get-AegisVerdict {
    param($State, $Pref, $Threats, $ThirdParty, $Services)
    $issues = @(); $warns = @()

    if ($State.CollectorError) {
        $issues += "Could not read Defender state: $($State.CollectorError). Defender may be uninstalled, blocked by GP, or this is Server Core without the AV role."
        return [PSCustomObject]@{ Verdict = 'AT RISK'; Class = 'crit'; Issues = @($issues); Warns = @($warns) }
    }

    if (-not $State.AntivirusEnabled)          { $issues += 'Defender antivirus is DISABLED.' }
    if (-not $State.AMServiceEnabled)          { $issues += 'Defender AM service is not running.' }
    if (-not $State.RealTimeProtectionEnabled) { $issues += 'Real-time protection is OFF.' }
    if (-not $State.IsTamperProtected -and -not $State.TamperProtected) {
        $issues += 'Tamper protection is OFF -- attackers can disable Defender from a local admin context.'
    }
    if ($null -ne $State.AntivirusSignatureAge -and $State.AntivirusSignatureAge -gt ($SignatureMaxAgeDays * 2)) {
        $issues += "Antivirus signatures are $($State.AntivirusSignatureAge) days old (> $($SignatureMaxAgeDays * 2) day red threshold)."
    }
    if ($Threats.UnresolvedHigh -gt 0) {
        $issues += "$($Threats.UnresolvedHigh) unresolved high/severe threat(s) recorded -- investigate before clearing."
    }

    if ($null -ne $State.AntivirusSignatureAge -and $State.AntivirusSignatureAge -gt $SignatureMaxAgeDays -and $State.AntivirusSignatureAge -le ($SignatureMaxAgeDays * 2)) {
        $warns += "Antivirus signatures are $($State.AntivirusSignatureAge) days old (> $SignatureMaxAgeDays day yellow threshold)."
    }
    if (-not $State.BehaviorMonitorEnabled)     { $warns += 'Behavior monitoring is off.' }
    if (-not $State.IoavProtectionEnabled)      { $warns += 'Downloaded-file scan (IOAV) is off.' }
    if (-not $State.OnAccessProtectionEnabled)  { $warns += 'On-access scanning is off.' }
    if (-not $State.NISEnabled)                 { $warns += 'Network Inspection (NIS) is off.' }
    if ($null -ne $State.QuickScanAge -and $State.QuickScanAge -gt 7) {
        $warns += "Last quick scan was $($State.QuickScanAge) day(s) ago."
    }
    if ($null -ne $State.FullScanAge -and $State.FullScanAge -gt 30) {
        $warns += "Last full scan was $($State.FullScanAge) day(s) ago."
    } elseif ($null -eq $State.FullScanAge) {
        $warns += 'No full scan recorded on this machine.'
    }

    if ($Pref -and -not $Pref.CollectorError) {
        if ([int]$Pref.MAPSReporting -eq 0)        { $warns += 'Cloud-delivered protection (MAPSReporting) is DISABLED.' }
        if ([int]$Pref.SubmitSamplesConsent -eq 2) { $warns += 'Sample submission is set to NEVER -- cloud blocks will miss novel threats.' }
        if ([int]$Pref.CloudBlockLevel -eq 0)      { $warns += 'Cloud block level is at default (lowest tier).' }

        $auditOnly = @($Pref.AsrRules | Where-Object { $_.Action -eq 2 })
        if ($auditOnly.Count -gt 0) {
            $warns += "$($auditOnly.Count) ASR rule(s) are in Audit-only mode -- detections logged but not blocked."
        }
        $totalExclusions = $Pref.ExclusionPath.Count + $Pref.ExclusionExtension.Count + $Pref.ExclusionProcess.Count + $Pref.ExclusionIpAddress.Count
        if ($totalExclusions -gt 20) {
            $warns += "$totalExclusions exclusions are configured -- a large exclusion footprint reduces effective protection coverage."
        }
        if ($Pref.DisableArchiveScanning)        { $warns += 'Archive (.zip / .iso / .7z) scanning is disabled.' }
        if ($Pref.DisableEmailScanning)          { $warns += 'Email scanning is disabled.' }
        if ($Pref.DisableScriptScanning)         { $warns += 'Script scanning is disabled.' }
        if ($Pref.DisableRemovableDriveScanning) { $warns += 'Removable-drive scanning is disabled.' }
        if ([int]$Pref.PUAProtection -eq 0)      { $warns += 'Potentially Unwanted Application (PUA) protection is DISABLED.' }
    }

    foreach ($svc in $Services) {
        if ($svc.Critical -and $svc.Status -ne 'Running') {
            $issues += "Critical service $($svc.Name) ($($svc.Friendly)) is $($svc.Status)."
        }
    }

    if ($State.RealTimeProtectionEnabled -and $ThirdParty.Available) {
        $rtThird = @($ThirdParty.Products | Where-Object { $_.RealTimeOn })
        if ($rtThird.Count -gt 0) {
            $warns += "$($rtThird.Count) third-party AV product(s) running in real-time alongside Defender -- only one should own real-time protection."
        }
    }

    $verdict = if ($issues.Count -gt 0) { 'AT RISK' } elseif ($warns.Count -gt 0) { 'ATTENTION NEEDED' } else { 'PROTECTED' }
    $class   = if ($issues.Count -gt 0) { 'crit' }   elseif ($warns.Count -gt 0) { 'warn' }             else { 'ok' }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $class; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN COLLECTORS
# ===========================

Write-Host "[*] Reading Defender state..." -ForegroundColor Magenta
$state = Get-DefenderState
if ($state.CollectorError) {
    Write-Host "[ERROR] Get-MpComputerStatus failed: $($state.CollectorError)" -ForegroundColor Red
    Write-Host "[!!]    Defender may be uninstalled, blocked by GP, or this is Server Core." -ForegroundColor Yellow
} else {
    Write-Host ("  Antivirus enabled    : {0}" -f $state.AntivirusEnabled)            -ForegroundColor $(if ($state.AntivirusEnabled) { 'Green' } else { 'Red' })
    Write-Host ("  Real-time protection : {0}" -f $state.RealTimeProtectionEnabled)   -ForegroundColor $(if ($state.RealTimeProtectionEnabled) { 'Green' } else { 'Red' })
    Write-Host ("  Tamper protection    : {0}" -f ($state.IsTamperProtected -or $state.TamperProtected)) -ForegroundColor $(if ($state.IsTamperProtected -or $state.TamperProtected) { 'Green' } else { 'Red' })
    Write-Host ("  AV sig age (days)    : {0}" -f $state.AntivirusSignatureAge) -ForegroundColor $(
        if ($null -eq $state.AntivirusSignatureAge) { 'Yellow' }
        elseif ($state.AntivirusSignatureAge -le $SignatureMaxAgeDays) { 'Green' }
        elseif ($state.AntivirusSignatureAge -le ($SignatureMaxAgeDays * 2)) { 'Yellow' }
        else { 'Red' })
    Write-Host ("  Engine               : {0}" -f $state.AMEngineVersion) -ForegroundColor Gray
}
Write-Host ""

Write-Host "[*] Reading Defender preferences (cloud, exclusions, ASR)..." -ForegroundColor Magenta
$pref = Get-DefenderPreference
if ($pref.CollectorError) {
    Write-Host "[!!] Get-MpPreference failed: $($pref.CollectorError)" -ForegroundColor Yellow
} else {
    Write-Host ("  Path exclusions      : {0}" -f $pref.ExclusionPath.Count)    -ForegroundColor Gray
    Write-Host ("  Process exclusions   : {0}" -f $pref.ExclusionProcess.Count) -ForegroundColor Gray
    Write-Host ("  ASR rules configured : {0}" -f $pref.AsrRules.Count)         -ForegroundColor Gray
}
Write-Host ""

Write-Host "[*] Reading threats and detections..." -ForegroundColor Magenta
$threats    = Get-ThreatHistorySnapshot
$detections = Get-RecentDetectionSnapshot
Write-Host ("  Threats in history   : {0}" -f $threats.Threats.Count)         -ForegroundColor Gray
Write-Host ("  Unresolved high/sev  : {0}" -f $threats.UnresolvedHigh) -ForegroundColor $(if ($threats.UnresolvedHigh -gt 0) { 'Red' } else { 'Green' })
Write-Host ("  Recent detections    : {0}" -f $detections.Detections.Count)   -ForegroundColor Gray
Write-Host ""

Write-Host "[*] Reading third-party AV (SecurityCenter2)..." -ForegroundColor Magenta
$thirdParty = Get-ThirdPartyAvProducts
if (-not $thirdParty.Available) {
    Write-Host "  SecurityCenter2 unavailable -- no third-party data (normal on Server SKUs)." -ForegroundColor Gray
} else {
    Write-Host ("  Registered products  : {0}" -f $thirdParty.Products.Count) -ForegroundColor Gray
    foreach ($p in $thirdParty.Products) {
        Write-Host ("    - {0}  RT: {1}  UpToDate: {2}" -f $p.DisplayName, $p.RealTimeOn, $p.UpToDate) -ForegroundColor $(if ($p.RealTimeOn) { 'Green' } else { 'Yellow' })
    }
}
Write-Host ""

Write-Host "[*] Reading service health..." -ForegroundColor Magenta
$services = Get-DefenderServiceStatus
foreach ($s in $services) {
    $color = if ($s.Status -eq 'Running')         { 'Green' }
             elseif ($s.Status -eq 'NotInstalled') { 'Gray' }
             elseif ($s.Critical)                  { 'Red' }
             else                                   { 'Yellow' }
    Write-Host ("  {0,-22} {1,-12} {2}" -f $s.Name, $s.Status, $s.Friendly) -ForegroundColor $color
}
Write-Host ""

Write-Host "[*] Reading Defender events (last $EventDays day(s))..." -ForegroundColor Magenta
$events = Get-DefenderEvents -Days $EventDays
Write-Host ("  Events captured      : {0}" -f $events.Events.Count) -ForegroundColor Gray
Write-Host ""

$verdict = Get-AegisVerdict -State $state -Pref $pref -Threats $threats -ThirdParty $thirdParty -Services $services

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AV / DEFENDER VERDICT" -ForegroundColor Cyan
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

$findingsList = ""
foreach ($i in $verdict.Issues) { $findingsList += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $findingsList += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $findingsList = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>Defender posture is clean -- real-time on, signatures fresh, no unresolved threats.</li>"
}

$prefAvailable = ($pref -and -not $pref.CollectorError)
if ($prefAvailable) {
    $mapsLabel       = switch ([int]$pref.MAPSReporting)        { 0 {'Disabled'} 1 {'Basic'} 2 {'Advanced (MAPS)'} default { "Code $($pref.MAPSReporting)" } }
    $sampleLabel     = switch ([int]$pref.SubmitSamplesConsent) { 0 {'Always prompt'} 1 {'Send safe samples'} 2 {'Never send'} 3 {'Send all samples'} default { "Code $($pref.SubmitSamplesConsent)" } }
    $cloudLevelLabel = switch ([int]$pref.CloudBlockLevel)      { 0 {'Default'} 2 {'High'} 4 {'High+'} 6 {'Zero-tolerance'} default { "Code $($pref.CloudBlockLevel)" } }
    $puaLabel        = switch ([int]$pref.PUAProtection)        { 0 {'Disabled'} 1 {'Block'} 2 {'Audit'} default { "Code $($pref.PUAProtection)" } }

    $cloudSampleBody = @"
<table>
  <tbody>
    <tr><th>MAPS Reporting</th><td>$(HtmlEncode $mapsLabel)</td></tr>
    <tr><th>Sample Submission Consent</th><td>$(HtmlEncode $sampleLabel)</td></tr>
    <tr><th>Cloud Block Level</th><td>$(HtmlEncode $cloudLevelLabel)</td></tr>
    <tr><th>Cloud Extended Timeout (s)</th><td>$(HtmlEncode "$($pref.CloudExtendedTimeout)")</td></tr>
    <tr><th>PUA Protection</th><td>$(HtmlEncode $puaLabel)</td></tr>
    <tr><th>Archive scanning</th><td>$(YnWarnBadge (-not $pref.DisableArchiveScanning))</td></tr>
    <tr><th>Email scanning</th><td>$(YnWarnBadge (-not $pref.DisableEmailScanning))</td></tr>
    <tr><th>Script scanning</th><td>$(YnWarnBadge (-not $pref.DisableScriptScanning))</td></tr>
    <tr><th>Removable-drive scanning</th><td>$(YnWarnBadge (-not $pref.DisableRemovableDriveScanning))</td></tr>
  </tbody>
</table>
"@
} else {
    $errSuffix = if ($pref.CollectorError) { " Collector error: $(HtmlEncode $pref.CollectorError)" } else { '' }
    $cloudSampleBody = "<div class='badge badge-warn' style='display:block;padding:8px 12px;'>Defender preferences could not be read -- cloud / sample submission posture is unknown.$errSuffix</div>"
}

$threatRows = ""
if ($threats.Threats.Count -eq 0) {
    $threatRows = "<tr><td colspan='6' style='text-align:center;color:#2ecc71;'>No threats recorded.</td></tr>"
} else {
    foreach ($t in $threats.Threats | Sort-Object SeverityID -Descending) {
        $sevBadge = if ($t.SeverityID -ge 4) { "<span class='badge badge-crit'>$(HtmlEncode $t.Severity)</span>" }
                    elseif ($t.SeverityID -ge 2) { "<span class='badge badge-warn'>$(HtmlEncode $t.Severity)</span>" }
                    else { "<span class='badge badge-neutral'>$(HtmlEncode $t.Severity)</span>" }
        $activeBadge = if ($t.IsActive) { "<span class='badge badge-crit'>Active</span>" } else { "<span class='badge badge-ok'>Resolved</span>" }
        $threatRows += "<tr><td>$(HtmlEncode $t.ThreatName)</td><td>$sevBadge</td><td>$activeBadge</td><td><code>$(HtmlEncode $t.ThreatID)</code></td><td>$(HtmlEncode "$($t.DetectionCount)")</td><td><code>$(HtmlEncode $t.Resources)</code></td></tr>"
    }
}

$detRows = ""
if ($detections.Detections.Count -eq 0) {
    $detRows = "<tr><td colspan='5' style='text-align:center;color:#2ecc71;'>No recent detections.</td></tr>"
} else {
    foreach ($d in $detections.Detections) {
        $okBadge = if ($d.ActionSuccess) { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-warn'>No</span>" }
        $detRows += "<tr><td>$(HtmlEncode "$($d.InitialDetectionTime)")</td><td>$(HtmlEncode $d.ProcessName)</td><td>$(HtmlEncode $d.DomainUser)</td><td><code>$(HtmlEncode $d.Resources)</code></td><td>$okBadge</td></tr>"
    }
}

function ExcTable {
    param([string]$Heading, [string[]]$Items)
    $cnt = @($Items).Count
    $body = "<div class='section-title' style='margin-top:14px;font-size:13px;'>$Heading ($cnt)</div>"
    if ($cnt -eq 0) {
        $body += "<div class='badge badge-ok' style='display:inline-block;padding:6px 10px;'>None configured.</div>"
    } else {
        $body += "<table><thead><tr><th>Value</th></tr></thead><tbody>"
        foreach ($x in $Items) { $body += "<tr><td><code>$(HtmlEncode $x)</code></td></tr>" }
        $body += "</tbody></table>"
    }
    return $body
}

if ($prefAvailable) {
    $exclusionsBlock =
        (ExcTable -Heading 'Path exclusions'      -Items $pref.ExclusionPath) +
        (ExcTable -Heading 'Extension exclusions' -Items $pref.ExclusionExtension) +
        (ExcTable -Heading 'Process exclusions'   -Items $pref.ExclusionProcess) +
        (ExcTable -Heading 'IP exclusions'        -Items $pref.ExclusionIpAddress)
} else {
    $exclusionsBlock = "<div class='badge badge-warn' style='display:block;padding:8px 12px;'>Could not read Defender preferences.</div>"
}

$asrRows = ""
if (-not $prefAvailable -or $pref.AsrRules.Count -eq 0) {
    $asrRows = "<tr><td colspan='3' style='text-align:center;color:#f39c12;'>No ASR rules configured (or preferences unavailable).</td></tr>"
} else {
    foreach ($r in $pref.AsrRules | Sort-Object Name) {
        $badge = switch ($r.Action) {
            1 { "<span class='badge badge-ok'>Block</span>" }
            2 { "<span class='badge badge-warn'>Audit</span>" }
            6 { "<span class='badge badge-warn'>Warn</span>" }
            0 { "<span class='badge badge-neutral'>Not Configured</span>" }
            default { "<span class='badge badge-neutral'>$(HtmlEncode $r.Label)</span>" }
        }
        $asrRows += "<tr><td>$(HtmlEncode $r.Name)</td><td>$badge</td><td><code>$(HtmlEncode $r.Id)</code></td></tr>"
    }
}

$tpRows = ""
if (-not $thirdParty.Available -or $thirdParty.Products.Count -eq 0) {
    $tpRows = "<tr><td colspan='4' style='text-align:center;color:#aaa;'>No third-party AV products registered.</td></tr>"
} else {
    foreach ($p in $thirdParty.Products) {
        $rt = if ($p.RealTimeOn) { "<span class='badge badge-ok'>On</span>" } else { "<span class='badge badge-warn'>Off</span>" }
        $up = if ($p.UpToDate)   { "<span class='badge badge-ok'>Yes</span>" } else { "<span class='badge badge-warn'>No</span>" }
        $tpRows += "<tr><td>$(HtmlEncode $p.DisplayName)</td><td>$rt</td><td>$up</td><td><code>$(HtmlEncode $p.ExePath)</code></td></tr>"
    }
}

$svcRows = ""
foreach ($s in $services) {
    $statusBadge = switch ($s.Status) {
        'Running'      { "<span class='badge badge-ok'>Running</span>" }
        'Stopped'      { if ($s.Critical) { "<span class='badge badge-crit'>Stopped</span>" } else { "<span class='badge badge-warn'>Stopped</span>" } }
        'NotInstalled' { "<span class='badge badge-neutral'>Not Installed</span>" }
        default        { "<span class='badge badge-warn'>$(HtmlEncode $s.Status)</span>" }
    }
    $crit = if ($s.Critical) { "<span class='badge badge-crit'>Critical</span>" } else { "<span class='badge badge-neutral'>Optional</span>" }
    $svcRows += "<tr><td><code>$(HtmlEncode $s.Name)</code></td><td>$(HtmlEncode $s.Friendly)</td><td>$statusBadge</td><td>$(HtmlEncode "$($s.StartType)")</td><td>$crit</td></tr>"
}

$evRows = ""
if (-not $events.Available) {
    $evRows = "<tr><td colspan='4' style='text-align:center;color:#f39c12;'>Defender Operational log unavailable.</td></tr>"
} elseif ($events.Events.Count -eq 0) {
    $evRows = "<tr><td colspan='4' style='text-align:center;color:#2ecc71;'>No Defender events in the last $EventDays day(s).</td></tr>"
} else {
    foreach ($e in $events.Events) {
        $lvlBadge = switch ($e.Level) {
            'Critical'    { "<span class='badge badge-crit'>$(HtmlEncode $e.Level)</span>" }
            'Error'       { "<span class='badge badge-crit'>$(HtmlEncode $e.Level)</span>" }
            'Warning'     { "<span class='badge badge-warn'>$(HtmlEncode $e.Level)</span>" }
            default       { "<span class='badge badge-neutral'>$(HtmlEncode $e.Level)</span>" }
        }
        $evRows += "<tr><td>$(HtmlEncode "$($e.TimeCreated)")</td><td>$(HtmlEncode "$($e.Id)")</td><td>$lvlBadge</td><td>$(HtmlEncode $e.Message)</td></tr>"
    }
}

$rtClass     = if ($state.RealTimeProtectionEnabled) { 'ok' } else { 'crit' }
$tpClass     = if ($state.IsTamperProtected -or $state.TamperProtected) { 'ok' } else { 'crit' }
$sigClass    = if ($state.AntivirusSignatureAge -le $SignatureMaxAgeDays) { 'ok' }
               elseif ($state.AntivirusSignatureAge -le ($SignatureMaxAgeDays * 2)) { 'warn' }
               else { 'crit' }
$threatClass = if ($threats.UnresolvedHigh -gt 0) { 'crit' } elseif ($threats.Threats.Count -gt 0) { 'warn' } else { 'ok' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>A.E.G.I.S. AV/Defender -- $env:COMPUTERNAME</title>
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
<h1>A.E.G.I.S. -- AV / Defender Health Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Posture</div></div>
  <div class="card $rtClass"><div class="val">$(if ($state.RealTimeProtectionEnabled) { 'On' } else { 'Off' })</div><div class="lbl">Real-time Protection</div></div>
  <div class="card $tpClass"><div class="val">$(if ($state.IsTamperProtected -or $state.TamperProtected) { 'On' } else { 'Off' })</div><div class="lbl">Tamper Protection</div></div>
  <div class="card $sigClass"><div class="val">$(if ($null -eq $state.AntivirusSignatureAge) { '?' } else { "$($state.AntivirusSignatureAge)d" })</div><div class="lbl">AV Signature Age</div></div>
  <div class="card $threatClass"><div class="val">$($threats.Threats.Count)</div><div class="lbl">Threats in History</div></div>
  <div class="card"><div class="val">$(HtmlEncode $state.AMRunningMode)</div><div class="lbl">AM Running Mode</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$findingsList</ul>

<div class="section-title">Defender Core State</div>
<table>
  <tbody>
    <tr><th>Antivirus Enabled</th><td>$(YnBadge $state.AntivirusEnabled)</td></tr>
    <tr><th>Antispyware Enabled</th><td>$(YnBadge $state.AntispywareEnabled)</td></tr>
    <tr><th>AM Service Enabled</th><td>$(YnBadge $state.AMServiceEnabled)</td></tr>
    <tr><th>AM Running Mode</th><td>$(HtmlEncode $state.AMRunningMode)</td></tr>
    <tr><th>AM Engine Version</th><td><code>$(HtmlEncode $state.AMEngineVersion)</code></td></tr>
    <tr><th>AM Service Version</th><td><code>$(HtmlEncode $state.AMServiceVersion)</code></td></tr>
    <tr><th>AM Product Version</th><td><code>$(HtmlEncode $state.AMProductVersion)</code></td></tr>
    <tr><th>Real-time Protection</th><td>$(YnBadge $state.RealTimeProtectionEnabled)</td></tr>
    <tr><th>Behavior Monitor</th><td>$(YnWarnBadge $state.BehaviorMonitorEnabled)</td></tr>
    <tr><th>IOAV (downloaded files)</th><td>$(YnWarnBadge $state.IoavProtectionEnabled)</td></tr>
    <tr><th>On-access Protection</th><td>$(YnWarnBadge $state.OnAccessProtectionEnabled)</td></tr>
    <tr><th>Network Inspection (NIS)</th><td>$(YnWarnBadge $state.NISEnabled)</td></tr>
    <tr><th>Tamper Protected</th><td>$(YnBadge ($state.IsTamperProtected -or $state.TamperProtected))</td></tr>
  </tbody>
</table>

<div class="section-title">Cloud &amp; Sample Submission</div>
$cloudSampleBody

<div class="section-title">Signatures</div>
<table>
  <thead><tr><th>Signature Set</th><th>Version</th><th>Last Updated</th><th>Age</th></tr></thead>
  <tbody>
    <tr><td>Antivirus</td><td><code>$(HtmlEncode $state.AntivirusSignatureVersion)</code></td><td>$(HtmlEncode "$($state.AntivirusSignatureLastUpdated)")</td><td>$(AgeBadge $state.AntivirusSignatureAge $SignatureMaxAgeDays ($SignatureMaxAgeDays * 2))</td></tr>
    <tr><td>Antispyware</td><td><code>$(HtmlEncode $state.AntispywareSignatureVersion)</code></td><td>$(HtmlEncode "$($state.AntispywareSignatureLastUpdated)")</td><td>$(AgeBadge $state.AntispywareSignatureAge $SignatureMaxAgeDays ($SignatureMaxAgeDays * 2))</td></tr>
    <tr><td>Network Inspection (NIS)</td><td><code>$(HtmlEncode $state.NISSignatureVersion)</code></td><td>$(HtmlEncode "$($state.NISSignatureLastUpdated)")</td><td>$(AgeBadge $state.NISSignatureAge $SignatureMaxAgeDays ($SignatureMaxAgeDays * 2))</td></tr>
  </tbody>
</table>

<div class="section-title">Scan History</div>
<table>
  <thead><tr><th>Scan</th><th>Last Started</th><th>Last Ended</th><th>Age</th></tr></thead>
  <tbody>
    <tr><td>Quick Scan</td><td>$(HtmlEncode "$($state.QuickScanStartTime)")</td><td>$(HtmlEncode "$($state.QuickScanEndTime)")</td><td>$(AgeBadge $state.QuickScanAge 7 30)</td></tr>
    <tr><td>Full Scan</td><td>$(HtmlEncode "$($state.FullScanStartTime)")</td><td>$(HtmlEncode "$($state.FullScanEndTime)")</td><td>$(AgeBadge $state.FullScanAge 30 90)</td></tr>
  </tbody>
</table>

<div class="section-title">Threat History ($($threats.Threats.Count) entries)</div>
<table>
  <thead><tr><th>Threat</th><th>Severity</th><th>State</th><th>Threat ID</th><th>Detections</th><th>Resources</th></tr></thead>
  <tbody>$threatRows</tbody>
</table>

<div class="section-title">Recent Detections ($($detections.Detections.Count) shown)</div>
<table>
  <thead><tr><th>Initial Detection</th><th>Process</th><th>User</th><th>Resources</th><th>Cleanup OK?</th></tr></thead>
  <tbody>$detRows</tbody>
</table>

<div class="section-title">Exclusions</div>
$exclusionsBlock

<div class="section-title">Attack Surface Reduction Rules ($(if ($prefAvailable) { $pref.AsrRules.Count } else { 0 }) configured)</div>
<table>
  <thead><tr><th>Rule</th><th>Mode</th><th>Rule ID</th></tr></thead>
  <tbody>$asrRows</tbody>
</table>

<div class="section-title">Third-Party AV Products (SecurityCenter2)</div>
<table>
  <thead><tr><th>Product</th><th>Real-time</th><th>Up to Date</th><th>Reporting EXE</th></tr></thead>
  <tbody>$tpRows</tbody>
</table>

<div class="section-title">Service Health</div>
<table>
  <thead><tr><th>Service</th><th>Description</th><th>Status</th><th>Start Type</th><th>Tier</th></tr></thead>
  <tbody>$svcRows</tbody>
</table>

<div class="section-title">Recent Defender Events (last $EventDays day(s))</div>
<table>
  <thead><tr><th>Time</th><th>Event ID</th><th>Level</th><th>Message</th></tr></thead>
  <tbody>$evRows</tbody>
</table>

<div class="footer">
  Generated by A.E.G.I.S. -- Technician Toolkit LiveConnect Suite
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
Write-Host "[OK] A.E.G.I.S. complete." -ForegroundColor Cyan
Write-Host ""
