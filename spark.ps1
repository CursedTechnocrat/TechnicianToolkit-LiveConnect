# spark.ps1 - S.P.A.R.K. — System Power Audit Reporting Kit
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
    S.P.A.R.K. — System Power Audit Reporting Kit
    LiveConnect-Compatible Laptop Battery Health Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Surfaces the three numbers that matter for a laptop battery's retirement
    decision: design capacity, current full-charge capacity, and cycle count.
    Pulls values from the ROOT\WMI battery classes (BatteryStaticData,
    BatteryFullChargedCapacity, BatteryCycleCount, BatteryStatus) and joins
    against Win32_Battery for the friendly device name. Reports health as a
    percentage of design, applies industry thresholds (80/60 capacity, 300/500
    cycles), and emits a dark-themed HTML report with a red/yellow/green
    replacement recommendation.

    Also runs powercfg /batteryreport to capture data the live WMI classes
    don't expose: per-battery serial number & manufacture date, full-charge
    capacity history (degradation trend), Windows' own runtime estimates at
    both current full charge and original design, and AC/DC usage totals.
    The full Microsoft-formatted HTML report and the parsed XML are saved
    alongside SPARK's HTML report.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

.USAGE
    PS C:\> .\spark.ps1
    PS C:\> .\spark.ps1 -ReportPath "C:\Temp"

.PARAMETERS
    -ReportPath   Folder where the HTML report (and powercfg files) are saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : P.Y.R.E. (main toolkit)
#>

param(
    [string]$ReportPath = "C:\Temp"
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$timestamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportFilename = "SPARK_${timestamp}.html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  S.P.A.R.K. -- System Power Audit Reporting Kit" -ForegroundColor Cyan
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

function Convert-BatteryChemistry {
    param($code)
    switch ([int]$code) {
        1 {'Other'} 2 {'Unknown'} 3 {'Lead Acid'} 4 {'Nickel Cadmium'}
        5 {'Nickel Metal Hydride'} 6 {'Lithium-ion'} 7 {'Zinc air'} 8 {'Lithium Polymer'}
        default {'Unknown'}
    }
}

function Convert-BatteryStatus {
    param($code)
    switch ([int]$code) {
        1 {'Discharging'} 2 {'AC Power (charging/charged)'} 3 {'Fully Charged'}
        4 {'Low'} 5 {'Critical'} 6 {'Charging'}
        7 {'Charging + High'} 8 {'Charging + Low'} 9 {'Charging + Critical'}
        10 {'Undefined'} 11 {'Partially Charged'}
        default {'Unknown'}
    }
}

function Convert-IsoDurationToMinutes {
    param([string]$Iso)
    if ([string]::IsNullOrWhiteSpace($Iso)) { return 0 }
    try { $ts = [System.Xml.XmlConvert]::ToTimeSpan($Iso); return [int]$ts.TotalMinutes }
    catch { return 0 }
}

function Format-Minutes {
    param([int]$Minutes)
    if ($Minutes -le 0) { return '0 min' }
    $d = [int][math]::Floor($Minutes / 1440)
    $h = [int][math]::Floor(($Minutes - $d * 1440) / 60)
    $m = $Minutes - $d * 1440 - $h * 60
    if ($d -gt 0) { return ('{0}d {1}h {2}m' -f $d, $h, $m) }
    if ($h -gt 0) { return ('{0}h {1}m' -f $h, $m) }
    return ('{0}m' -f $m)
}

# Thresholds
$script:CapOkPct   = 80.0
$script:CapWarnPct = 60.0
$script:CycOk      = 300
$script:CycWarn    = 500

# ===========================
# COLLECTORS
# ===========================

function Get-BatteryHealthRecords {
    $win32 = @()
    try { $win32 = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue) } catch {}

    $static = @(); $full = @(); $cycle = @(); $status = @()
    try { $static = @(Get-CimInstance -Namespace 'ROOT\WMI' -ClassName BatteryStaticData          -ErrorAction SilentlyContinue) } catch {}
    try { $full   = @(Get-CimInstance -Namespace 'ROOT\WMI' -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue) } catch {}
    try { $cycle  = @(Get-CimInstance -Namespace 'ROOT\WMI' -ClassName BatteryCycleCount          -ErrorAction SilentlyContinue) } catch {}
    try { $status = @(Get-CimInstance -Namespace 'ROOT\WMI' -ClassName BatteryStatus              -ErrorAction SilentlyContinue) } catch {}

    if ($win32.Count -eq 0 -and $static.Count -eq 0) { return @() }

    $instances = New-Object System.Collections.Generic.HashSet[string]
    foreach ($set in @($static, $full, $cycle, $status)) {
        foreach ($item in $set) { if ($item.InstanceName) { [void]$instances.Add($item.InstanceName) } }
    }

    if ($instances.Count -eq 0) {
        return @($win32 | ForEach-Object {
            [PSCustomObject]@{
                InstanceName = $_.DeviceID; Name = $_.Name; Caption = $_.Caption
                Chemistry = Convert-BatteryChemistry $_.Chemistry
                DesignCapacity = $null; FullCapacity = $null; CycleCount = $null; HealthPercent = $null
                ChargeRate = $null; DischargeRate = $null; Voltage = $null
                Charging = $null; Discharging = $null
                StatusText = Convert-BatteryStatus $_.BatteryStatus
            }
        })
    }

    $rows = foreach ($inst in $instances) {
        $s = $static | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
        $f = $full   | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
        $c = $cycle  | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
        $t = $status | Where-Object { $_.InstanceName -eq $inst } | Select-Object -First 1
        $wi = $win32 | Where-Object { $inst -like "*$($_.DeviceID)*" } | Select-Object -First 1

        $design  = if ($s) { [int64]$s.DesignedCapacity } else { $null }
        $fullCap = if ($f) { [int64]$f.FullChargedCapacity } else { $null }
        $cycles  = if ($c) { [int]$c.CycleCount } else { $null }
        $health  = if ($design -and $fullCap -and $design -gt 0) { [math]::Round(($fullCap / $design) * 100, 1) } else { $null }

        [PSCustomObject]@{
            InstanceName   = $inst
            Name           = if ($wi) { $wi.Name } else { $inst }
            Caption        = if ($wi) { $wi.Caption } else { '' }
            Chemistry      = if ($wi) { Convert-BatteryChemistry $wi.Chemistry } else { 'Unknown' }
            DesignCapacity = $design
            FullCapacity   = $fullCap
            CycleCount     = $cycles
            HealthPercent  = $health
            ChargeRate     = if ($t) { [int]$t.ChargeRate } else { $null }
            DischargeRate  = if ($t) { [int]$t.DischargeRate } else { $null }
            Voltage        = if ($t) { [int]$t.Voltage } else { $null }
            Charging       = if ($t) { [bool]$t.Charging } else { $null }
            Discharging    = if ($t) { [bool]$t.Discharging } else { $null }
            StatusText     = if ($wi) { Convert-BatteryStatus $wi.BatteryStatus } else { 'Unknown' }
        }
    }
    return @($rows)
}

function Invoke-PowerCfgBatteryReport {
    param([string]$LogDir, [string]$Timestamp)
    $xmlPath  = Join-Path $LogDir "SPARK_powercfg_${Timestamp}.xml"
    $htmlPath = Join-Path $LogDir "SPARK_powercfg_${Timestamp}.html"

    $result = [PSCustomObject]@{
        XmlPath = $xmlPath; HtmlPath = $htmlPath
        HtmlAvailable = $false; Available = $false; Error = $null
        Batteries = @(); Estimates = $null; CapacityHistory = @(); UsageSummary = $null
    }

    try {
        $null = & powercfg.exe /batteryreport /xml /output $xmlPath 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $xmlPath)) {
            $result.Error = "powercfg /batteryreport /xml exit code $LASTEXITCODE"
            return $result
        }
    } catch {
        $result.Error = "powercfg invocation failed: $($_.Exception.Message)"
        return $result
    }

    try {
        $null = & powercfg.exe /batteryreport /output $htmlPath 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $htmlPath)) { $result.HtmlAvailable = $true }
    } catch {}

    try { $xml = [xml](Get-Content $xmlPath -Raw -ErrorAction Stop) }
    catch {
        $result.Error = "could not read powercfg XML: $($_.Exception.Message)"
        return $result
    }

    $report = $xml.BatteryReport
    if (-not $report) {
        $result.Error = 'powercfg XML had no BatteryReport root element.'
        return $result
    }

    $batteries = @()
    if ($report.Batteries -and $report.Batteries.Battery) {
        foreach ($b in @($report.Batteries.Battery)) {
            $batteries += [PSCustomObject]@{
                Id                 = [string]$b.Id
                Manufacturer       = [string]$b.Manufacturer
                SerialNumber       = [string]$b.SerialNumber
                ManufactureDate    = [string]$b.ManufactureDate
                Chemistry          = [string]$b.Chemistry
                DesignCapacity     = if ($b.DesignCapacity)     { [int64]$b.DesignCapacity }     else { $null }
                FullChargeCapacity = if ($b.FullChargeCapacity) { [int64]$b.FullChargeCapacity } else { $null }
            }
        }
    }
    $result.Batteries = @($batteries)

    $rt = $report.RuntimeEstimates
    if ($rt) {
        $atFull   = $rt.FullChargeCapacity
        $atDesign = $rt.DesignCapacity
        $result.Estimates = [PSCustomObject]@{
            ActiveAtFull    = if ($atFull   -and $atFull.ActiveRuntime)      { Convert-IsoDurationToMinutes $atFull.ActiveRuntime }      else { $null }
            StandbyAtFull   = if ($atFull   -and $atFull.ConnectedStandby)   { Convert-IsoDurationToMinutes $atFull.ConnectedStandby }   else { $null }
            ActiveAtDesign  = if ($atDesign -and $atDesign.ActiveRuntime)    { Convert-IsoDurationToMinutes $atDesign.ActiveRuntime }    else { $null }
            StandbyAtDesign = if ($atDesign -and $atDesign.ConnectedStandby) { Convert-IsoDurationToMinutes $atDesign.ConnectedStandby } else { $null }
        }
    }

    $history = @()
    if ($report.HistoryEntries -and $report.HistoryEntries.HistoryEntry) {
        foreach ($h in @($report.HistoryEntries.HistoryEntry)) {
            $history += [PSCustomObject]@{
                StartDate          = [string]$h.StartDate
                EndDate            = [string]$h.EndDate
                DesignCapacity     = if ($h.DesignCapacity)     { [int64]$h.DesignCapacity }     else { $null }
                FullChargeCapacity = if ($h.FullChargeCapacity) { [int64]$h.FullChargeCapacity } else { $null }
                CycleCount         = if ($h.CycleCount)         { [int]$h.CycleCount }            else { $null }
            }
        }
    }
    $result.CapacityHistory = @($history | Sort-Object EndDate -Descending | Select-Object -First 12)

    if ($report.RuntimeHistory -and $report.RuntimeHistory.RuntimeEntry) {
        $entries = @($report.RuntimeHistory.RuntimeEntry)
        $totActDc = 0; $totActAc = 0; $totCsDc = 0; $totCsAc = 0
        foreach ($e in $entries) {
            $totActDc += (Convert-IsoDurationToMinutes $e.ActiveDcTime)
            $totActAc += (Convert-IsoDurationToMinutes $e.ActiveAcTime)
            $totCsDc  += (Convert-IsoDurationToMinutes $e.CsDcTime)
            $totCsAc  += (Convert-IsoDurationToMinutes $e.CsAcTime)
        }
        $result.UsageSummary = [PSCustomObject]@{
            EntryCount = $entries.Count
            ActiveDcMin = $totActDc; ActiveAcMin = $totActAc
            StandbyDcMin = $totCsDc; StandbyAcMin = $totCsAc
        }
    }

    $result.Available = $true
    return $result
}

# ===========================
# VERDICT
# ===========================

function Get-CapClass([PSCustomObject]$B) {
    if (-not $B.HealthPercent) { return 'neutral' }
    if ($B.HealthPercent -ge $script:CapOkPct)    { return 'ok' }
    elseif ($B.HealthPercent -ge $script:CapWarnPct) { return 'warn' }
    else { return 'crit' }
}
function Get-CycClass([PSCustomObject]$B) {
    if ($null -eq $B.CycleCount) { return 'neutral' }
    if ($B.CycleCount -lt $script:CycOk)   { return 'ok' }
    elseif ($B.CycleCount -lt $script:CycWarn) { return 'warn' }
    else { return 'crit' }
}

function Get-SparkVerdict {
    param([array]$Batteries)
    if ($Batteries.Count -eq 0) {
        return [PSCustomObject]@{
            Verdict = 'NO BATTERY'; Class = 'neutral'; Issues = @()
            Warns = @('No battery hardware detected — this is expected on desktops and servers.')
        }
    }
    $issues = @(); $warns = @(); $worst = 'ok'
    foreach ($b in $Batteries) {
        $capClass = Get-CapClass $b
        $cycClass = Get-CycClass $b
        if ($capClass -eq 'crit') {
            $issues += "Battery '$($b.Name)' is at $($b.HealthPercent)% of design capacity — below the $script:CapWarnPct% replacement threshold."
            $worst = 'crit'
        } elseif ($capClass -eq 'warn' -and $worst -ne 'crit') {
            $warns += "Battery '$($b.Name)' is at $($b.HealthPercent)% of design capacity — plan replacement within the next upgrade cycle."
            $worst = 'warn'
        }
        if ($cycClass -eq 'crit') {
            $issues += "Battery '$($b.Name)' has $($b.CycleCount) charge cycles — past the $script:CycWarn-cycle comfort limit."
            $worst = 'crit'
        } elseif ($cycClass -eq 'warn' -and $worst -ne 'crit') {
            $warns += "Battery '$($b.Name)' has $($b.CycleCount) charge cycles — approaching the $script:CycWarn-cycle limit."
            if ($worst -ne 'crit') { $worst = 'warn' }
        }
        if ($null -eq $b.HealthPercent -and $null -eq $b.CycleCount) {
            $warns += "Battery '$($b.Name)' reports no design/cycle data — firmware exposes only basic status."
        }
    }
    $verdict = switch ($worst) {
        'crit' { 'REPLACE NOW' } 'warn' { 'REPLACEMENT SOON' } 'neutral' { 'DATA INCOMPLETE' } default { 'HEALTHY' }
    }
    return [PSCustomObject]@{ Verdict = $verdict; Class = $worst; Issues = @($issues); Warns = @($warns) }
}

# ===========================
# RUN
# ===========================

Write-Host "[*] Reading battery hardware..." -ForegroundColor Magenta
$batteries = Get-BatteryHealthRecords

if ($batteries.Count -eq 0) {
    Write-Host "[!!] No battery hardware detected (desktop / server / VM)." -ForegroundColor Yellow
} else {
    foreach ($b in $batteries) {
        Write-Host "  $($b.Name)  ($($b.Chemistry))" -ForegroundColor Cyan
        $design = if ($b.DesignCapacity) { "$([math]::Round($b.DesignCapacity / 1000, 1)) Wh" } else { 'n/a' }
        $full   = if ($b.FullCapacity)   { "$([math]::Round($b.FullCapacity / 1000, 1)) Wh"   } else { 'n/a' }
        Write-Host ("    Design     : {0}" -f $design) -ForegroundColor Gray
        Write-Host ("    Full charge: {0}" -f $full)   -ForegroundColor Gray
        if ($null -ne $b.HealthPercent) {
            $cls = Get-CapClass $b
            $col = switch ($cls) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'crit' { 'Red' } default { 'Gray' } }
            Write-Host ("    Health     : {0}%" -f $b.HealthPercent) -ForegroundColor $col
        }
        if ($null -ne $b.CycleCount) {
            $cls = Get-CycClass $b
            $col = switch ($cls) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'crit' { 'Red' } default { 'Gray' } }
            Write-Host ("    Cycles     : {0}" -f $b.CycleCount) -ForegroundColor $col
        }
        Write-Host ("    Status     : {0}" -f $b.StatusText) -ForegroundColor Gray
    }
}
Write-Host ""

$verdict = Get-SparkVerdict -Batteries $batteries

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  BATTERY VERDICT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$vColor = switch ($verdict.Class) { 'ok' { 'Green' } 'warn' { 'Yellow' } 'crit' { 'Red' } default { 'Gray' } }
Write-Host "  $($verdict.Verdict)" -ForegroundColor $vColor
foreach ($i in $verdict.Issues) { Write-Host "    [!!] $i" -ForegroundColor Red }
foreach ($w in $verdict.Warns)  { Write-Host "    [~ ] $w" -ForegroundColor Yellow }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    Write-Host "    [+ ] All batteries within healthy thresholds." -ForegroundColor Green
}
Write-Host ""

$powerCfg = $null
if ($batteries.Count -gt 0) {
    Write-Host "[*] Running powercfg /batteryreport (XML + HTML)..." -ForegroundColor Magenta
    $powerCfg = Invoke-PowerCfgBatteryReport -LogDir $ReportPath -Timestamp $timestamp
    if ($powerCfg.Available) {
        Write-Host "[OK] powercfg XML parsed:  $($powerCfg.XmlPath)" -ForegroundColor Green
        if ($powerCfg.HtmlAvailable) { Write-Host "[OK] powercfg HTML saved: $($powerCfg.HtmlPath)" -ForegroundColor Green }
        if ($powerCfg.Estimates) {
            $e = $powerCfg.Estimates
            if ($null -ne $e.ActiveAtFull)   { Write-Host ("    Active runtime (full charge)  : {0}" -f (Format-Minutes $e.ActiveAtFull))   -ForegroundColor Gray }
            if ($null -ne $e.ActiveAtDesign) { Write-Host ("    Active runtime (design)       : {0}" -f (Format-Minutes $e.ActiveAtDesign)) -ForegroundColor Gray }
        }
        Write-Host ("    Capacity history entries      : {0}" -f $powerCfg.CapacityHistory.Count) -ForegroundColor Gray
    } else {
        Write-Host "[!!] powercfg /batteryreport unavailable: $($powerCfg.Error)" -ForegroundColor Yellow
    }
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$bestHealth  = if ($batteries.Count -gt 0) { ($batteries | Where-Object { $_.HealthPercent } | Measure-Object -Property HealthPercent -Maximum).Maximum } else { $null }
$worstHealth = if ($batteries.Count -gt 0) { ($batteries | Where-Object { $_.HealthPercent } | Measure-Object -Property HealthPercent -Minimum).Minimum } else { $null }
$maxCycles   = if ($batteries.Count -gt 0) { ($batteries | Where-Object { $null -ne $_.CycleCount } | Measure-Object -Property CycleCount -Maximum).Maximum } else { $null }

$rows = ""
if ($batteries.Count -eq 0) {
    $rows = "<tr><td colspan='8' style='text-align:center;color:#aaa;'>No battery hardware detected.</td></tr>"
} else {
    foreach ($b in $batteries) {
        $capClass = Get-CapClass $b
        $cycClass = Get-CycClass $b
        $capBadge = if ($null -eq $b.HealthPercent) { "<span class='badge badge-neutral'>n/a</span>" } else { "<span class='badge badge-$capClass'>$($b.HealthPercent)%</span>" }
        $cycBadge = if ($null -eq $b.CycleCount)    { "<span class='badge badge-neutral'>n/a</span>" } else { "<span class='badge badge-$cycClass'>$($b.CycleCount)</span>" }
        $design   = if ($b.DesignCapacity) { "$([math]::Round($b.DesignCapacity / 1000, 1)) Wh" } else { 'n/a' }
        $full     = if ($b.FullCapacity)   { "$([math]::Round($b.FullCapacity / 1000, 1)) Wh"   } else { 'n/a' }
        $voltage  = if ($b.Voltage)        { "$([math]::Round($b.Voltage / 1000, 2)) V"         } else { 'n/a' }
        $rows += "<tr><td>$(HtmlEncode $b.Name)</td><td>$(HtmlEncode $b.Chemistry)</td><td>$design</td><td>$full</td><td>$capBadge</td><td>$cycBadge</td><td>$voltage</td><td>$(HtmlEncode $b.StatusText)</td></tr>"
    }
}

$verdictBlock = ""
foreach ($i in $verdict.Issues) { $verdictBlock += "<li class='badge badge-crit' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $i)</li>" }
foreach ($w in $verdict.Warns)  { $verdictBlock += "<li class='badge badge-warn' style='display:block;margin:4px 0;padding:6px 10px;'>$(HtmlEncode $w)</li>" }
if ($verdict.Issues.Count -eq 0 -and $verdict.Warns.Count -eq 0) {
    $verdictBlock = "<li class='badge badge-ok' style='display:block;margin:4px 0;padding:6px 10px;'>All batteries are within healthy thresholds.</li>"
}

$pcSection = ""
if ($powerCfg -and $powerCfg.Available) {
    if ($powerCfg.Batteries.Count -gt 0) {
        $bRows = ""
        foreach ($pb in $powerCfg.Batteries) {
            $design = if ($pb.DesignCapacity)     { "$([math]::Round($pb.DesignCapacity / 1000, 1)) Wh" } else { 'n/a' }
            $full   = if ($pb.FullChargeCapacity) { "$([math]::Round($pb.FullChargeCapacity / 1000, 1)) Wh" } else { 'n/a' }
            $mfg    = if ([string]::IsNullOrWhiteSpace($pb.ManufactureDate)) { 'n/a' } else { HtmlEncode $pb.ManufactureDate }
            $serial = if ([string]::IsNullOrWhiteSpace($pb.SerialNumber))    { 'n/a' } else { HtmlEncode $pb.SerialNumber }
            $bRows += "<tr><td>$(HtmlEncode $pb.Id)</td><td>$(HtmlEncode $pb.Manufacturer)</td><td><code>$serial</code></td><td>$mfg</td><td>$(HtmlEncode $pb.Chemistry)</td><td>$design</td><td>$full</td></tr>"
        }
        $pcSection += @"
<div class="section-title">Battery Identification (powercfg)</div>
<table>
  <thead><tr><th>Battery ID</th><th>Manufacturer</th><th>Serial</th><th>Manufactured</th><th>Chemistry</th><th>Design</th><th>Full Charge</th></tr></thead>
  <tbody>$bRows</tbody>
</table>
"@
    }

    if ($powerCfg.Estimates) {
        $e = $powerCfg.Estimates
        $activeFull   = if ($null -ne $e.ActiveAtFull)    { Format-Minutes $e.ActiveAtFull }    else { 'n/a' }
        $activeDes    = if ($null -ne $e.ActiveAtDesign)  { Format-Minutes $e.ActiveAtDesign }  else { 'n/a' }
        $standbyFull  = if ($null -ne $e.StandbyAtFull)   { Format-Minutes $e.StandbyAtFull }   else { 'n/a' }
        $standbyDes   = if ($null -ne $e.StandbyAtDesign) { Format-Minutes $e.StandbyAtDesign } else { 'n/a' }
        $lostActive   = if ($null -ne $e.ActiveAtFull -and $null -ne $e.ActiveAtDesign) { Format-Minutes ([math]::Max(0, $e.ActiveAtDesign - $e.ActiveAtFull)) } else { 'n/a' }
        $pcSection += @"
<div class="section-title">Runtime Estimates (Windows-modeled)</div>
<table>
  <thead><tr><th>Scenario</th><th>At full charge</th><th>At design capacity</th></tr></thead>
  <tbody>
    <tr><td>Active use</td><td>$activeFull</td><td>$activeDes</td></tr>
    <tr><td>Connected standby</td><td>$standbyFull</td><td>$standbyDes</td></tr>
  </tbody>
</table>
<div style="margin-top:14px;color:#aaa;font-size:13px;"><strong>Active runtime lost to wear:</strong> $lostActive (full charge vs design)</div>
"@
    }

    if ($powerCfg.CapacityHistory.Count -gt 0) {
        $hRows = ""
        foreach ($h in $powerCfg.CapacityHistory) {
            $period = "$(HtmlEncode $h.StartDate) &rarr; $(HtmlEncode $h.EndDate)"
            $design = if ($h.DesignCapacity)     { "$([math]::Round($h.DesignCapacity / 1000, 1)) Wh" } else { 'n/a' }
            $full   = if ($h.FullChargeCapacity) { "$([math]::Round($h.FullChargeCapacity / 1000, 1)) Wh" } else { 'n/a' }
            $pct = if ($h.DesignCapacity -and $h.FullChargeCapacity -and $h.DesignCapacity -gt 0) {
                $p = [math]::Round(($h.FullChargeCapacity / $h.DesignCapacity) * 100, 1)
                $cls = if ($p -ge $script:CapOkPct) { 'ok' } elseif ($p -ge $script:CapWarnPct) { 'warn' } else { 'crit' }
                "<span class='badge badge-$cls'>$p%</span>"
            } else { "<span class='badge badge-neutral'>n/a</span>" }
            $cyc = if ($null -ne $h.CycleCount) { "$($h.CycleCount)" } else { 'n/a' }
            $hRows += "<tr><td>$period</td><td>$design</td><td>$full</td><td>$pct</td><td>$cyc</td></tr>"
        }
        $pcSection += @"
<div class="section-title">Capacity History (most recent $($powerCfg.CapacityHistory.Count) entries)</div>
<table>
  <thead><tr><th>Period</th><th>Design</th><th>Full Charge</th><th>Health %</th><th>Cycles</th></tr></thead>
  <tbody>$hRows</tbody>
</table>
"@
    }

    if ($powerCfg.UsageSummary) {
        $u = $powerCfg.UsageSummary
        $totalDc = $u.ActiveDcMin + $u.StandbyDcMin
        $totalAc = $u.ActiveAcMin + $u.StandbyAcMin
        $totalAll = $totalDc + $totalAc
        $dcPct = if ($totalAll -gt 0) { [math]::Round(($totalDc / $totalAll) * 100, 1) } else { 0 }
        $pcSection += @"
<div class="section-title">Recent Usage ($($u.EntryCount) periods recorded)</div>
<table>
  <thead><tr><th>Mode</th><th>On battery (DC)</th><th>Plugged in (AC)</th></tr></thead>
  <tbody>
    <tr><td>Active</td><td>$(Format-Minutes $u.ActiveDcMin)</td><td>$(Format-Minutes $u.ActiveAcMin)</td></tr>
    <tr><td>Connected standby</td><td>$(Format-Minutes $u.StandbyDcMin)</td><td>$(Format-Minutes $u.StandbyAcMin)</td></tr>
  </tbody>
</table>
<div style="margin-top:14px;color:#aaa;font-size:13px;"><strong>Time on battery:</strong> $dcPct% of recorded runtime</div>
"@
    }

    if ($powerCfg.HtmlAvailable) {
        $href = HtmlEncode ([System.IO.Path]::GetFileName($powerCfg.HtmlPath))
        $pcSection += "<div class='section-title'>Full Microsoft Report</div><div style='color:#aaa;'><a href='$href' style='color:#00d4ff;'><code>$href</code></a> (saved alongside this report)</div>"
    }
} elseif ($powerCfg -and $powerCfg.Error) {
    $pcSection = "<div class='section-title'>powercfg Battery Report</div><div class='badge badge-warn' style='display:block;padding:8px 12px;'>powercfg unavailable: $(HtmlEncode $powerCfg.Error)</div>"
}

$bestCard  = if ($null -ne $bestHealth)  { "$bestHealth%"  } else { 'n/a' }
$worstCard = if ($null -ne $worstHealth) { "$worstHealth%" } else { 'n/a' }
$cycCard   = if ($null -ne $maxCycles)   { "$maxCycles"    } else { 'n/a' }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>S.P.A.R.K. Battery -- $env:COMPUTERNAME</title>
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
<h1>S.P.A.R.K. -- Battery Health Report</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime &nbsp;|&nbsp; Verdict: <strong>$(HtmlEncode $verdict.Verdict)</strong></div>

<div class="summary">
  <div class="card $($verdict.Class)"><div class="val">$(HtmlEncode $verdict.Verdict)</div><div class="lbl">Battery Verdict</div></div>
  <div class="card"><div class="val">$($batteries.Count)</div><div class="lbl">Batteries</div></div>
  <div class="card"><div class="val">$bestCard</div><div class="lbl">Best Health</div></div>
  <div class="card"><div class="val">$worstCard</div><div class="lbl">Worst Health</div></div>
  <div class="card"><div class="val">$cycCard</div><div class="lbl">Max Cycle Count</div></div>
  <div class="card"><div class="val">$($script:CapOkPct)% / $($script:CycOk)</div><div class="lbl">OK Thresholds</div></div>
</div>

<div class="section-title">Verdict &amp; Findings</div>
<ul>$verdictBlock</ul>

<div class="section-title">Battery Details ($($batteries.Count) battery/batteries)</div>
<table>
  <thead><tr><th>Name</th><th>Chemistry</th><th>Design</th><th>Full Charge</th><th>Health %</th><th>Cycles</th><th>Voltage</th><th>Status</th></tr></thead>
  <tbody>$rows</tbody>
</table>
<div style="margin-top:18px;color:#aaa;font-size:13px;">
  <strong>Thresholds</strong>:
  Capacity &ge; $($script:CapOkPct)% healthy, $($script:CapWarnPct)-$($script:CapOkPct)% plan replacement, &lt; $($script:CapWarnPct)% replace now.&nbsp;&nbsp;
  Cycles &lt; $($script:CycOk) healthy, $($script:CycOk)-$($script:CycWarn) plan replacement, &ge; $($script:CycWarn) replace now.
</div>

$pcSection

<div class="footer">
  Generated by S.P.A.R.K. -- Technician Toolkit LiveConnect Suite
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
if ($powerCfg -and $powerCfg.Available) {
    if ($powerCfg.HtmlAvailable) { Write-Host "  POWERCFG HTML: $($powerCfg.HtmlPath)" -ForegroundColor Cyan }
    Write-Host "  POWERCFG XML : $($powerCfg.XmlPath)" -ForegroundColor Cyan
}
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] S.P.A.R.K. complete." -ForegroundColor Cyan
Write-Host ""
