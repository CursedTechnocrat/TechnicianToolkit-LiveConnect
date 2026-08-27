# purge.ps1 - P.U.R.G.E. — PowerShell Unified Reclamation & Garbage Elimination
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
    P.U.R.G.E. — PowerShell Unified Reclamation & Garbage Elimination
    LiveConnect-Compatible Disk Cleanup Tool for PowerShell 5.1+

.DESCRIPTION
    Cleans common junk accumulation points on Windows: user and system temp
    folders, Windows Update download cache, the Recycle Bin, and browser
    caches (Chrome, Edge, Firefox). Shows estimated size per category, runs
    the selected categories, and writes a CSV log of bytes freed.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\purge.ps1
    PS C:\> .\purge.ps1 -Categories "1,3,5"
    PS C:\> .\purge.ps1 -WhatIf
    PS C:\> .\purge.ps1 -LogPath "C:\Temp"

.PARAMETERS
    -Categories   Categories to clean: comma-separated numbers (e.g. "1,3,5") or "A" for all. Default: A.
    -WhatIf       Scan only; report sizes without deleting anything.
    -LogPath      Folder where the CSV log is saved (default: C:\Temp)

.CATEGORIES
    1   User Temp Folders ($env:TEMP and %LOCALAPPDATA%\Temp for the running user)
    2   System Temp Folder (C:\Windows\Temp)
    3   Windows Update Cache (C:\Windows\SoftwareDistribution\Download — stops/starts wuauserv)
    4   Recycle Bin (all drives)
    5   Browser Caches (Chrome, Edge, Firefox — all user profiles)

.NOTES
    Version : 1.0
    Suite   : Technician Toolkit — LiveConnect
    Mirrors : C.L.E.A.N.S.E. (main toolkit)
#>

param(
    [string]$Categories = "A",
    [switch]$WhatIf,
    [string]$LogPath = "C:\Temp"
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script must be run as Administrator." -ForegroundColor Red
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ExecutionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logFilename   = "PURGE_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

if (-not (Test-Path $LogPath)) {
    try { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create log folder '$LogPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
$logFullPath = Join-Path $LogPath $logFilename

Write-Host ""
Write-Host "  P.U.R.G.E. -- PowerShell Unified Reclamation & Garbage Elimination" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As     : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time       : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Mode       : $(if ($WhatIf) { 'DRY RUN (-WhatIf)' } else { 'EXECUTE' })" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Gray' })
Write-Host "  Categories : $Categories" -ForegroundColor Gray
Write-Host "  Log        : $logFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

function Format-Bytes([long]$b) {
    if ($null -eq $b -or $b -le 0) { return '0 B' }
    $units = 'B','KB','MB','GB','TB'; $i = 0
    while ($b -ge 1024 -and $i -lt $units.Count - 1) { $b = $b / 1024; $i++ }
    return ('{0:N1} {1}' -f $b, $units[$i])
}

function Get-FolderSize {
    param([string[]]$Paths)
    $total = 0L
    foreach ($p in $Paths) {
        if (Test-Path $p) {
            try {
                $sum = (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($sum) { $total += $sum }
            } catch {}
        }
    }
    return $total
}

function Remove-FolderContents {
    param([string[]]$Paths)
    $freed = 0L
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        $items = Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $size = if ($item.PSIsContainer) {
                    (Get-ChildItem -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                } else { $item.Length }
                if ($null -eq $size) { $size = 0 }
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $freed += $size
            } catch {}
        }
    }
    return $freed
}

# ===========================
# RESOLVE TARGETS
# ===========================

function Get-UserTempPaths {
    $paths = @($env:TEMP)
    if ($env:LOCALAPPDATA) { $paths += Join-Path $env:LOCALAPPDATA 'Temp' }
    return $paths | Select-Object -Unique | Where-Object { $_ -and (Test-Path $_) }
}

function Get-BrowserCachePaths {
    $paths = @()
    $profiles = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue
    foreach ($profile in $profiles) {
        $base = $profile.FullName
        $chromeBase = Join-Path $base 'AppData\Local\Google\Chrome\User Data'
        if (Test-Path $chromeBase) {
            Get-ChildItem $chromeBase -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(Default|Profile)' } |
                ForEach-Object { $paths += Join-Path $_.FullName 'Cache'; $paths += Join-Path $_.FullName 'Code Cache' }
        }
        $edgeBase = Join-Path $base 'AppData\Local\Microsoft\Edge\User Data'
        if (Test-Path $edgeBase) {
            Get-ChildItem $edgeBase -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(Default|Profile)' } |
                ForEach-Object { $paths += Join-Path $_.FullName 'Cache'; $paths += Join-Path $_.FullName 'Code Cache' }
        }
        $ffProfiles = Join-Path $base 'AppData\Local\Mozilla\Firefox\Profiles'
        if (Test-Path $ffProfiles) {
            Get-ChildItem $ffProfiles -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { $paths += Join-Path $_.FullName 'cache2' }
        }
    }
    return $paths | Where-Object { Test-Path $_ }
}

# ===========================
# SCAN
# ===========================

Write-Host "[*] Scanning cleanup targets..." -ForegroundColor Magenta

$userTempPaths    = Get-UserTempPaths
$sysTempPaths     = @('C:\Windows\Temp')
$wuCachePaths     = @('C:\Windows\SoftwareDistribution\Download')
$browserCachePaths = Get-BrowserCachePaths

$userTempSize     = Get-FolderSize -Paths $userTempPaths
$sysTempSize      = Get-FolderSize -Paths $sysTempPaths
$wuCacheSize      = Get-FolderSize -Paths $wuCachePaths
$browserCacheSize = Get-FolderSize -Paths $browserCachePaths

$recycleBinSize = 0L
try {
    $shell = New-Object -ComObject Shell.Application
    $bin   = $shell.Namespace(0xA)
    if ($bin) {
        $sum = ($bin.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
        if ($sum) { $recycleBinSize = [long]$sum }
    }
} catch {}

$totalSize = $userTempSize + $sysTempSize + $wuCacheSize + $recycleBinSize + $browserCacheSize

Write-Host ""
Write-Host "  Cleanup categories:" -ForegroundColor Cyan
Write-Host ("    [1] User Temp Folders          {0,12}" -f (Format-Bytes $userTempSize)) -ForegroundColor Gray
Write-Host ("    [2] System Temp (Windows\Temp) {0,12}" -f (Format-Bytes $sysTempSize))  -ForegroundColor Gray
Write-Host ("    [3] Windows Update Cache       {0,12}" -f (Format-Bytes $wuCacheSize))  -ForegroundColor Gray
Write-Host ("    [4] Recycle Bin                {0,12}" -f (Format-Bytes $recycleBinSize)) -ForegroundColor Gray
Write-Host ("    [5] Browser Caches             {0,12}" -f (Format-Bytes $browserCacheSize)) -ForegroundColor Gray
Write-Host ("    [A] All of the above           {0,12}" -f (Format-Bytes $totalSize))    -ForegroundColor Yellow
Write-Host ""

# Parse category selection
$sel = $Categories.ToUpper().Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$runAll = $sel -contains 'A'

# ===========================
# EXECUTE
# ===========================

$logRows  = @()
$totalFreed = 0L

function Invoke-CleanCategory {
    param([string]$Id, [string]$Label, [long]$EstimatedSize, [scriptblock]$Action)
    $shouldRun = $runAll -or ($sel -contains $Id)
    if (-not $shouldRun) {
        Write-Host ("  [-] Skipping {0}" -f $Label) -ForegroundColor Gray
        $script:logRows += [PSCustomObject]@{
            Category = $Label
            Action   = 'SKIPPED'
            Estimated = (Format-Bytes $EstimatedSize)
            Freed    = (Format-Bytes 0)
            FreedBytes = 0
        }
        return
    }
    if ($WhatIf) {
        Write-Host ("  [~] WhatIf: would clean {0} -- estimated {1}" -f $Label, (Format-Bytes $EstimatedSize)) -ForegroundColor Yellow
        $script:logRows += [PSCustomObject]@{
            Category = $Label
            Action   = 'WHATIF'
            Estimated = (Format-Bytes $EstimatedSize)
            Freed    = (Format-Bytes 0)
            FreedBytes = 0
        }
        return
    }
    Write-Host ("  [*] Cleaning {0}..." -f $Label) -ForegroundColor Magenta
    $freed = & $Action
    if ($null -eq $freed) { $freed = 0 }
    $script:totalFreed += [long]$freed
    Write-Host ("  [OK] {0} -- freed {1}" -f $Label, (Format-Bytes $freed)) -ForegroundColor Green
    $script:logRows += [PSCustomObject]@{
        Category = $Label
        Action   = 'CLEANED'
        Estimated = (Format-Bytes $EstimatedSize)
        Freed    = (Format-Bytes $freed)
        FreedBytes = [long]$freed
    }
}

Invoke-CleanCategory -Id '1' -Label 'User Temp Folders' -EstimatedSize $userTempSize -Action {
    Remove-FolderContents -Paths $userTempPaths
}

Invoke-CleanCategory -Id '2' -Label 'System Temp' -EstimatedSize $sysTempSize -Action {
    Remove-FolderContents -Paths $sysTempPaths
}

Invoke-CleanCategory -Id '3' -Label 'Windows Update Cache' -EstimatedSize $wuCacheSize -Action {
    $wuSvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
    $wasRunning = $wuSvc -and $wuSvc.Status -eq 'Running'
    if ($wasRunning) { Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue }
    $f = Remove-FolderContents -Paths $wuCachePaths
    if ($wasRunning) { Start-Service -Name wuauserv -ErrorAction SilentlyContinue }
    $f
}

Invoke-CleanCategory -Id '4' -Label 'Recycle Bin' -EstimatedSize $recycleBinSize -Action {
    $before = $recycleBinSize
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch {}
    $before
}

Invoke-CleanCategory -Id '5' -Label 'Browser Caches' -EstimatedSize $browserCacheSize -Action {
    Remove-FolderContents -Paths $browserCachePaths
}

# ===========================
# LOG
# ===========================

try {
    $logRows | Export-Csv -Path $logFullPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Host ""
    Write-Host "[OK] Log saved: $logFullPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Could not save log: $($_.Exception.Message)" -ForegroundColor Red
}

# ===========================
# SUMMARY
# ===========================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  P.U.R.G.E. SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
if ($WhatIf) {
    Write-Host "  Mode               : DRY RUN -- no files were deleted." -ForegroundColor Yellow
    Write-Host ("  Estimated reclaim : {0}" -f (Format-Bytes $totalSize)) -ForegroundColor Yellow
} else {
    Write-Host ("  Total space freed  : {0}" -f (Format-Bytes $totalFreed)) -ForegroundColor Green
}
Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  LOG PATH: $logFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] P.U.R.G.E. complete." -ForegroundColor Cyan
Write-Host ""
