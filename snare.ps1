# snare.ps1 - S.N.A.R.E. — Surveys Native Autoruns & Records Entries
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
    S.N.A.R.E. — Surveys Native Autoruns & Records Entries
    LiveConnect-Compatible Persistence / Autoruns Audit Tool for PowerShell 5.1+

.DESCRIPTION
    Sweeps the standard Windows persistence surfaces -- Run/RunOnce keys,
    Startup folders, Scheduled Tasks, Services, WMI event subscriptions,
    Image File Execution Options, and Winlogon hijack points -- and
    inventories every entry. Each row is enriched with target existence
    and Authenticode signature status. Saves a dark-themed HTML report.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\snare.ps1
    PS C:\> .\snare.ps1 -ReportPath "C:\Temp"
    PS C:\> .\snare.ps1 -ReportPath "\\server\share\Reports"

.PARAMETERS
    -ReportPath   Folder where the HTML report is saved (default: C:\Temp)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : T.A.L.O.N. (main toolkit)
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
$reportFilename = "SNARE_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

if (-not (Test-Path $ReportPath)) {
    try { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create report folder '$ReportPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$reportFullPath = Join-Path $ReportPath $reportFilename

Write-Host ""
Write-Host "  S.N.A.R.E. -- Surveys Native Autoruns & Records Entries" -ForegroundColor Cyan
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

function Get-EntryEnrichment {
    param([string]$CommandLine)

    $result = [PSCustomObject]@{
        TargetPath      = $null
        TargetExists    = $false
        Signer          = $null
        SignatureStatus = 'Unknown'
        IsMicrosoft     = $false
    }

    if (-not $CommandLine) { return $result }

    $path = $null
    $trim = $CommandLine.Trim()
    if ($trim.StartsWith('"')) {
        $close = $trim.IndexOf('"', 1)
        if ($close -gt 0) { $path = $trim.Substring(1, $close - 1) }
    } else {
        $path = ($trim -split '\s+', 2)[0]
    }
    if (-not $path) { return $result }

    try { $path = [Environment]::ExpandEnvironmentVariables($path) } catch {}
    $result.TargetPath = $path

    if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) {
        $result.TargetExists = $true
        try {
            $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
            $result.SignatureStatus = $sig.Status.ToString()
            if ($sig.SignerCertificate) {
                $result.Signer      = $sig.SignerCertificate.Subject
                $result.IsMicrosoft = $sig.SignerCertificate.Subject -match 'CN=Microsoft'
            }
        } catch {
            $result.SignatureStatus = 'Error'
        }
    }

    return $result
}

function New-PersistenceRow {
    param(
        [string]$Category,
        [string]$Source,
        [string]$Name,
        [string]$Command,
        [hashtable]$Extra = @{}
    )
    $enr = Get-EntryEnrichment -CommandLine $Command
    $row = [PSCustomObject]@{
        Category        = $Category
        Source          = $Source
        Name            = $Name
        Command         = $Command
        TargetPath      = $enr.TargetPath
        TargetExists    = $enr.TargetExists
        SignatureStatus = $enr.SignatureStatus
        Signer          = $enr.Signer
        IsMicrosoft     = $enr.IsMicrosoft
    }
    foreach ($k in $Extra.Keys) {
        $row | Add-Member -NotePropertyName $k -NotePropertyValue $Extra[$k] -Force
    }
    return $row
}

# ===========================
# COLLECTORS
# ===========================

function Get-RunKeyEntries {
    $keys = @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';                     Source = 'HKCU\Run' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce';                 Source = 'HKCU\RunOnce' }
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';                     Source = 'HKLM\Run' }
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';                 Source = 'HKLM\RunOnce' }
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';         Source = 'HKLM\Wow6432\Run' }
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce';     Source = 'HKLM\Wow6432\RunOnce' }
    )
    $rows = foreach ($k in $keys) {
        if (-not (Test-Path $k.Path)) { continue }
        $props = Get-ItemProperty -Path $k.Path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($n in $props.PSObject.Properties.Name) {
            if ($n -in @('PSPath','PSParentPath','PSChildName','PSProvider','PSDrive')) { continue }
            New-PersistenceRow -Category 'Run Key' -Source $k.Source -Name $n -Command ($props.$n)
        }
    }
    return @($rows)
}

function Get-StartupFolderEntries {
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup');       Source = 'User Startup' }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Source = 'All Users Startup' }
    )
    $rows = foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path $f.Path)) { continue }
        foreach ($item in (Get-ChildItem -LiteralPath $f.Path -File -Force -ErrorAction SilentlyContinue)) {
            $target = $item.FullName
            if ($item.Extension -eq '.lnk') {
                try {
                    $shell = New-Object -ComObject WScript.Shell
                    $sc    = $shell.CreateShortcut($item.FullName)
                    if ($sc.TargetPath) { $target = $sc.TargetPath }
                } catch {}
            }
            New-PersistenceRow -Category 'Startup Folder' -Source $f.Source -Name $item.Name -Command $target
        }
    }
    return @($rows)
}

function Get-ServiceEntries {
    $svcs = Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.StartMode -match 'Auto' }
    $rows = foreach ($s in $svcs) {
        if (-not $s.PathName) { continue }
        New-PersistenceRow -Category 'Service' -Source 'Win32_Service' -Name $s.Name -Command $s.PathName -Extra @{
            DisplayName = $s.DisplayName
            StartMode   = $s.StartMode
            State       = $s.State
            Account     = $s.StartName
        }
    }
    return @($rows)
}

function Get-ScheduledTaskEntries {
    try { $tasks = Get-ScheduledTask -ErrorAction Stop } catch { return @() }
    $rows = foreach ($t in $tasks) {
        if ($t.TaskPath -like '\Microsoft\*') { continue }
        foreach ($a in $t.Actions) {
            $cmd = if ($a.Execute) { $a.Execute } else { '' }
            if ($a.Arguments) { $cmd = "$cmd $($a.Arguments)" }
            New-PersistenceRow -Category 'Scheduled Task' -Source $t.TaskPath -Name $t.TaskName -Command $cmd -Extra @{
                State    = "$($t.State)"
                TaskPath = $t.TaskPath
                Triggers = (@($t.Triggers | ForEach-Object { $_.TriggerType }) -join ', ')
                RunAs    = $t.Principal.UserId
            }
        }
    }
    return @($rows)
}

function Get-WmiPersistenceEntries {
    $rows = @()
    try {
        $filters   = Get-CimInstance -Namespace root\subscription -ClassName __EventFilter           -ErrorAction SilentlyContinue
        $consumers = Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer         -ErrorAction SilentlyContinue
        $bindings  = Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue
    } catch { return @() }

    foreach ($b in $bindings) {
        $cmd = 'N/A'
        if ($b.Consumer -and $b.Consumer -match 'Name=') {
            $cname = ($b.Consumer -replace '.*Name="([^"]+)".*','$1')
            $match = $consumers | Where-Object { $_.Name -eq $cname } | Select-Object -First 1
            if ($match) {
                if     ($match.CommandLineTemplate) { $cmd = $match.CommandLineTemplate }
                elseif ($match.ScriptText)          { $cmd = "(ActiveScript): " + (($match.ScriptText -split "`n") | Select-Object -First 1) }
                elseif ($match.ExecutablePath)      { $cmd = $match.ExecutablePath }
            }
        }
        $rows += New-PersistenceRow -Category 'WMI Subscription' -Source 'root\subscription' -Name $b.Filter -Command $cmd
    }

    if ((@($bindings).Count -eq 0) -and ((@($filters).Count -gt 0) -or (@($consumers).Count -gt 0))) {
        foreach ($f in $filters) {
            $rows += New-PersistenceRow -Category 'WMI Subscription' -Source 'root\subscription' -Name "Filter: $($f.Name)" -Command $f.Query
        }
    }
    return @($rows)
}

function Get-IfeoEntries {
    $ifeoRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    if (-not (Test-Path $ifeoRoot)) { return @() }
    $rows = foreach ($sub in Get-ChildItem $ifeoRoot -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
        if ($props -and $props.Debugger) {
            New-PersistenceRow -Category 'IFEO Debugger' -Source 'HKLM\IFEO' -Name $sub.PSChildName -Command $props.Debugger
        }
    }
    return @($rows)
}

function Get-WinlogonEntries {
    $rows = @()
    try {
        $wl = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
        if ($wl.Shell)    { $rows += New-PersistenceRow -Category 'Winlogon' -Source 'HKLM\Winlogon' -Name 'Shell'    -Command $wl.Shell }
        if ($wl.Userinit) { $rows += New-PersistenceRow -Category 'Winlogon' -Source 'HKLM\Winlogon' -Name 'Userinit' -Command $wl.Userinit }
    } catch {}
    try {
        $init = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -ErrorAction Stop
        if ($init.AppInit_DLLs)     { $rows += New-PersistenceRow -Category 'Winlogon' -Source 'HKLM\Windows' -Name 'AppInit_DLLs'     -Command $init.AppInit_DLLs }
        if ($init.LoadAppInit_DLLs) { $rows += New-PersistenceRow -Category 'Winlogon' -Source 'HKLM\Windows' -Name 'LoadAppInit_DLLs' -Command "$($init.LoadAppInit_DLLs)" }
    } catch {}
    return @($rows)
}

# ===========================
# COLLECTION
# ===========================

$entries = @()

Write-Host "[*] Run / RunOnce keys..."         -ForegroundColor Magenta; $entries += Get-RunKeyEntries
Write-Host "[*] Startup folders..."             -ForegroundColor Magenta; $entries += Get-StartupFolderEntries
Write-Host "[*] Services (auto-start)..."       -ForegroundColor Magenta; $entries += Get-ServiceEntries
Write-Host "[*] Scheduled tasks..."             -ForegroundColor Magenta; $entries += Get-ScheduledTaskEntries
Write-Host "[*] WMI event subscriptions..."     -ForegroundColor Magenta; $entries += Get-WmiPersistenceEntries
Write-Host "[*] IFEO debugger hooks..."         -ForegroundColor Magenta; $entries += Get-IfeoEntries
Write-Host "[*] Winlogon hijack points..."      -ForegroundColor Magenta; $entries += Get-WinlogonEntries

Write-Host ""
Write-Host "[OK] Collected $($entries.Count) persistence entry/entries." -ForegroundColor Green
Write-Host ""

# ===========================
# SUMMARY
# ===========================

$byCat = $entries | Group-Object Category | Sort-Object Name

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ENTRIES BY CATEGORY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($g in $byCat) {
    Write-Host ("  {0,-22} {1,6}" -f $g.Name, $g.Count) -ForegroundColor Gray
}
Write-Host ""

$missing    = @($entries | Where-Object { -not $_.TargetExists -and $_.TargetPath }).Count
$unsigned   = @($entries | Where-Object { $_.TargetExists -and $_.SignatureStatus -ne 'Valid' }).Count
$thirdParty = @($entries | Where-Object { $_.TargetExists -and $_.SignatureStatus -eq 'Valid' -and -not $_.IsMicrosoft }).Count
$microsoft  = @($entries | Where-Object { $_.IsMicrosoft }).Count

if ($missing -gt 0) {
    Write-Host "[!!] $missing entry/entries point to a target NOT on disk." -ForegroundColor Red
}
if ($unsigned -gt 0) {
    Write-Host "[!!] $unsigned entry/entries have an unsigned target or signature error." -ForegroundColor Yellow
}
if ($missing -eq 0 -and $unsigned -eq 0) {
    Write-Host "[OK] Every entry is signed and its target is present." -ForegroundColor Green
}
Write-Host ""

# ===========================
# HTML REPORT
# ===========================

Write-Host "[*] Generating HTML report..." -ForegroundColor Magenta

$summaryTitle = if ($missing -gt 0 -or $unsigned -gt 0) { 'REVIEW FINDINGS' } else { 'CLEAN' }
$summaryClass = if ($missing -gt 0) { 'crit' } elseif ($unsigned -gt 0) { 'warn' } else { 'ok' }

$catBlocks = ""
foreach ($g in $byCat) {
    $catRows = ""
    foreach ($r in ($g.Group | Sort-Object Source, Name)) {
        $sigBadge = switch ($r.SignatureStatus) {
            'Valid'        { if ($r.IsMicrosoft) { "<span class='badge badge-ok'>MS signed</span>" } else { "<span class='badge badge-neutral'>3rd-party signed</span>" } }
            'NotSigned'    { "<span class='badge badge-warn'>Unsigned</span>" }
            'HashMismatch' { "<span class='badge badge-crit'>Tampered</span>" }
            'Error'        { "<span class='badge badge-warn'>Sig error</span>" }
            'Unknown'      { "<span class='badge badge-neutral'>n/a</span>" }
            default        { "<span class='badge badge-warn'>$(HtmlEncode $r.SignatureStatus)</span>" }
        }
        $existBadge = if (-not $r.TargetPath)   { "<span class='badge badge-neutral'>n/a</span>" }
                      elseif ($r.TargetExists)  { "<span class='badge badge-ok'>Present</span>" }
                      else                      { "<span class='badge badge-crit'>Missing</span>" }
        $catRows += @"
        <tr>
            <td>$(HtmlEncode $r.Source)</td>
            <td>$(HtmlEncode $r.Name)</td>
            <td><code>$(HtmlEncode $r.Command)</code></td>
            <td>$existBadge</td>
            <td>$sigBadge</td>
        </tr>
"@
    }
    $catBlocks += @"
<div class="section-title">$(HtmlEncode $g.Name)  <span style='color:#888;font-weight:normal;'>($($g.Count))</span></div>
<table>
  <thead>
    <tr><th>Source</th><th>Name</th><th>Command</th><th>Target</th><th>Signature</th></tr>
  </thead>
  <tbody>
    $catRows
  </tbody>
</table>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>S.N.A.R.E. Persistence Audit -- $env:COMPUTERNAME</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', Consolas, monospace; font-size: 14px; padding: 24px; }
  h1 { color: #00d4ff; font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #888; font-size: 13px; margin-bottom: 24px; }
  .summary { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 28px; }
  .card { background: #16213e; border: 1px solid #0f3460; border-radius: 8px; padding: 16px 24px; min-width: 120px; text-align: center; }
  .card .val { font-size: 24px; font-weight: bold; color: #00d4ff; }
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
<h1>S.N.A.R.E. -- Persistence / Autoruns Audit</h1>
<div class="subtitle">Machine: <strong>$env:COMPUTERNAME</strong> &nbsp;|&nbsp; Generated: $ExecutionTime</div>

<div class="summary">
  <div class="card $summaryClass"><div class="val">$(HtmlEncode $summaryTitle)</div><div class="lbl">Outcome</div></div>
  <div class="card"><div class="val">$($entries.Count)</div><div class="lbl">Total Entries</div></div>
  <div class="card ok"><div class="val">$microsoft</div><div class="lbl">MS-signed</div></div>
  <div class="card"><div class="val">$thirdParty</div><div class="lbl">3rd-party Signed</div></div>
  <div class="card $(if ($unsigned -gt 0) { 'warn' } else { 'ok' })"><div class="val">$unsigned</div><div class="lbl">Unsigned / Sig Error</div></div>
  <div class="card $(if ($missing -gt 0) { 'crit' } else { 'ok' })"><div class="val">$missing</div><div class="lbl">Missing Targets</div></div>
</div>

$catBlocks

<div class="footer">
  Generated by S.N.A.R.E. -- Technician Toolkit LiveConnect Suite
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
Write-Host "[OK] S.N.A.R.E. complete." -ForegroundColor Cyan
Write-Host ""
