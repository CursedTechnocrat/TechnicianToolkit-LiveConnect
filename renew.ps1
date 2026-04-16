<#
.SYNOPSIS
    R.E.N.E.W. — Remotely Enacted Non-interactive Engine for Windows-updates
    LiveConnect-Compatible Windows Update Manager for PowerShell 5.1+

.DESCRIPTION
    Automates Windows Update detection and installation with no user intervention.
    Handles power settings, PSWindowsUpdate module setup, update deployment, and
    reboot detection. Disables sleep for the duration and restores settings on exit.
    PSWindowsUpdate module is auto-installed if missing.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no countdown timers, no Read-Host or ReadKey calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\renew.ps1
    PS C:\> .\renew.ps1 -AutoReboot

.PARAMETERS
    -AutoReboot   Automatically reboot the machine if a reboot is required after
                  updates install. Default: report reboot needed but do NOT reboot.

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
    [switch]$AutoReboot
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
# TRANSCRIPT LOGGING
# ===========================

$transcriptPath = $null
try {
    $transcriptPath = "$env:TEMP\RENEW_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Start-Transcript -Path $transcriptPath | Out-Null
}
catch {
    $transcriptPath = $null
}

# ===========================
# HEADER
# ===========================

$ExecutionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Write-Host ""
Write-Host "  R.E.N.E.W. -- Remotely Enacted Non-interactive Engine for Windows-updates" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As     : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time       : $ExecutionTime" -ForegroundColor Gray
Write-Host "  AutoReboot : $AutoReboot" -ForegroundColor Gray
if ($transcriptPath) {
    Write-Host "  Log        : $transcriptPath" -ForegroundColor Gray
}
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""

# ===========================
# STEP 1: POWER SETTINGS
# ===========================

Write-Host "[1/4] Configuring power settings..." -ForegroundColor Magenta

$script:originalMonitorAC = 10
$script:originalMonitorDC = 5

try {
    $monitorQuery = powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 2>&1
    $acLine = $monitorQuery | Where-Object { $_ -match "Current AC Power Setting Index" }
    $dcLine = $monitorQuery | Where-Object { $_ -match "Current DC Power Setting Index" }
    if ($acLine) {
        $acHex = ($acLine -replace ".*:\s*0x", "").Trim()
        $script:originalMonitorAC = [math]::Round([convert]::ToInt32($acHex, 16) / 60)
    }
    if ($dcLine) {
        $dcHex = ($dcLine -replace ".*:\s*0x", "").Trim()
        $script:originalMonitorDC = [math]::Round([convert]::ToInt32($dcHex, 16) / 60)
    }
    Write-Host "    Monitor timeout saved (AC: $($script:originalMonitorAC)m, DC: $($script:originalMonitorDC)m)" -ForegroundColor Gray

    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    powercfg /change monitor-timeout-ac 0
    powercfg /change monitor-timeout-dc 0
    Write-Host "[OK] Power settings configured (sleep disabled for update run)." -ForegroundColor Green
}
catch {
    Write-Host "[!!] Error configuring power settings: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# ===========================
# STEP 2: PSWINDOWSUPDATE
# ===========================

Write-Host "[2/4] Ensuring PSWindowsUpdate module is available..." -ForegroundColor Magenta

try {
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if ($null -eq $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
        Write-Host "    Installing NuGet package provider..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
        Write-Host "    [OK] NuGet provider installed." -ForegroundColor Green
    }
    else {
        Write-Host "    [OK] NuGet provider available." -ForegroundColor Green
    }

    $module = Get-Module -Name PSWindowsUpdate -ListAvailable
    if ($null -eq $module) {
        Write-Host "    Installing PSWindowsUpdate module (this may take a moment)..." -ForegroundColor Gray
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
        Write-Host "[OK] PSWindowsUpdate installed." -ForegroundColor Green
    }
    else {
        Write-Host "    Checking for module updates..." -ForegroundColor Gray
        Update-Module -Name PSWindowsUpdate -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[OK] PSWindowsUpdate is up to date." -ForegroundColor Green
    }
}
catch {
    Write-Host "[ERROR] Failed to prepare PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
    if ($transcriptPath) { try { Stop-Transcript } catch {} }
    exit 1
}

Write-Host ""

# ===========================
# STEP 3: IMPORT MODULE
# ===========================

Write-Host "[3/4] Importing PSWindowsUpdate module..." -ForegroundColor Magenta
try {
    Import-Module -Name PSWindowsUpdate -Force
    Write-Host "[OK] PSWindowsUpdate imported." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to import PSWindowsUpdate: $($_.Exception.Message)" -ForegroundColor Red
    if ($transcriptPath) { try { Stop-Transcript } catch {} }
    exit 1
}

Write-Host ""

# ===========================
# STEP 4: INSTALL UPDATES
# ===========================

Write-Host "[4/4] Scanning and installing Windows Updates..." -ForegroundColor Magenta
Write-Host "    (This may take several minutes)" -ForegroundColor Gray
Write-Host ""

try {
    $updates = Get-WindowsUpdate -NotCategory "Drivers"

    if ($null -eq $updates -or $updates.Count -eq 0) {
        Write-Host "[OK] No updates available. System is up to date." -ForegroundColor Green
    }
    else {
        Write-Host "    Found $($updates.Count) update(s) to install:" -ForegroundColor Gray
        $updates | ForEach-Object { Write-Host "    * $($_.Title)" -ForegroundColor Gray }
        Write-Host ""

        Install-WindowsUpdate -NotCategory "Drivers" -AutoReboot:$false -Confirm:$false

        Write-Host "[OK] Windows Updates installed." -ForegroundColor Green
    }
}
catch {
    Write-Host "[ERROR] Update installation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  UPDATE INSTALLATION COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ===========================
# REBOOT CHECK
# ===========================

Write-Host "Checking reboot status..." -ForegroundColor Magenta

$rebootRequired = $false
try {
    $rebootStatus   = Get-WindowsUpdateRebootStatus
    $rebootRequired = $rebootStatus.RebootRequired
}
catch {
    Write-Host "[!!] Could not determine reboot status: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($rebootRequired) {
    Write-Host ""
    Write-Host "  [!!] REBOOT REQUIRED" -ForegroundColor Yellow
    Write-Host "       Last Boot: $($rebootStatus.LastBootUpTime)" -ForegroundColor Gray
    Write-Host ""

    if ($AutoReboot) {
        Write-Host "  [*] -AutoReboot set -- restoring power settings and rebooting in 10 seconds..." -ForegroundColor Yellow
        Write-Host ""

        powercfg /change monitor-timeout-ac $script:originalMonitorAC
        powercfg /change monitor-timeout-dc $script:originalMonitorDC

        if ($transcriptPath) { try { Stop-Transcript } catch {} }
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Host "  [*] -AutoReboot not set -- skipping reboot." -ForegroundColor Yellow
        Write-Host "  [!!] Reboot this machine when ready: Restart-Computer" -ForegroundColor Yellow
        Write-Host ""
    }
}
else {
    Write-Host "[OK] No reboot required." -ForegroundColor Green
    Write-Host ""
}

# ===========================
# RESTORE POWER SETTINGS
# ===========================

Write-Host "Restoring power settings..." -ForegroundColor Magenta
try {
    powercfg /change monitor-timeout-ac $script:originalMonitorAC
    powercfg /change monitor-timeout-dc $script:originalMonitorDC
    Write-Host "[OK] Monitor timeout restored (AC: $($script:originalMonitorAC)m, DC: $($script:originalMonitorDC)m)" -ForegroundColor Green
}
catch {
    Write-Host "[!!] Could not restore monitor timeout: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""

# ===========================
# SUMMARY
# ===========================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RENEW DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Machine         : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Reboot Required : $rebootRequired" -ForegroundColor $(if ($rebootRequired) { 'Yellow' } else { 'Green' })
if ($transcriptPath) {
    Write-Host ""
    Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
    Write-Host "  LOG PATH: $transcriptPath" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
}
Write-Host ""
Write-Host "[OK] R.E.N.E.W. complete." -ForegroundColor Cyan
Write-Host ""

# ===========================
# STOP TRANSCRIPT
# ===========================

if ($transcriptPath) {
    try { Stop-Transcript } catch {}
}
