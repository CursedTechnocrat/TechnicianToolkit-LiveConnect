<#
.SYNOPSIS
    N.E.X.U.S. — Network-Executed Xpress Unattended Setup
    LiveConnect-Compatible Software Deployment for PowerShell 5.1+

.DESCRIPTION
    Installs required software packages silently using Windows Package Manager
    (winget) or Chocolatey. Designed for fully unattended execution via
    Kaseya VSA LiveConnect — no interactive prompts, no menu navigation.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\nexus.ps1
    PS C:\> .\nexus.ps1 -PackageManager chocolatey

.PARAMETERS
    -PackageManager   Package manager to use: 'winget' (default) or 'chocolatey'

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
    [ValidateSet('winget', 'chocolatey')]
    [string]$PackageManager = 'winget'
)

# ===========================
# CONFIGURATION
# ===========================

$ExecutionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$RequiredSoftware = @(
    "Microsoft.Teams",
    "Microsoft.Office",
    "7zip.7zip",
    "Google.Chrome",
    "Adobe.Acrobat.Reader.64-bit",
    "Zoom.Zoom"
)

$RequiredSoftwareChoco = @(
    "microsoft-teams",
    "microsoft365apps",
    "7zip",
    "googlechrome",
    "adobereader",
    "zoom"
)

# ===========================
# HEADER
# ===========================

Write-Host ""
Write-Host "  N.E.X.U.S. -- Network-Executed Xpress Unattended Setup" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  Time:            $ExecutionTime" -ForegroundColor Gray
Write-Host "  Package Manager: $PackageManager" -ForegroundColor Gray
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""

# ===========================
# INSTALLATION TRACKING
# ===========================

$InstallationLog = New-Object System.Collections.ArrayList

function Add-InstallationRecord {
    param(
        [string]$Software,
        [string]$Status,
        [string]$Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    )

    $record = New-Object PSObject -Property @{
        Timestamp = $Timestamp
        Software  = $Software
        Status    = $Status
    }

    [void]$InstallationLog.Add($record)
}

# ===========================
# PACKAGE MANAGER CHECK
# ===========================

function Test-ChocolateyAvailable {
    try {
        $chocoVersion = & choco --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Chocolatey available: v$chocoVersion" -ForegroundColor Green
            return $true
        }
    }
    catch {}

    Write-Host "[!!] Chocolatey not found — installing now..." -ForegroundColor Yellow

    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path", "User")

        $chocoVersion = & choco --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Chocolatey installed: v$chocoVersion" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "[ERROR] Chocolatey install failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $false
}

function Test-WingetAvailable {
    try {
        $wingetVersion = & winget --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Winget available: $wingetVersion" -ForegroundColor Green
            return $true
        }
    }
    catch {}

    Write-Host "[!!] Winget not found — attempting install..." -ForegroundColor Yellow

    try {
        $wingetUrl = "https://aka.ms/getwinget"
        $tempFile  = Join-Path $env:TEMP "GetWinget.ps1"

        (New-Object System.Net.WebClient).DownloadFile($wingetUrl, $tempFile)

        if (Test-Path $tempFile) {
            & $tempFile
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Winget installed successfully" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "[ERROR] Winget install failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $false
}

# ===========================
# INSTALLATION
# ===========================

function Install-Software {
    param([string[]]$SoftwareList)

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Installing Required Packages" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($item in $SoftwareList) {
        Write-Host "[*] Installing: $item..." -ForegroundColor Gray

        try {
            if ($PackageManager -eq "chocolatey") {
                $output = & choco install $item -y 2>&1
            }
            else {
                $output = & winget install -e --id $item --accept-source-agreements --accept-package-agreements -h 2>&1
            }

            $exitCode  = $LASTEXITCODE
            $installTime = (Get-Date).ToString('HH:mm:ss')

            if ($exitCode -eq 0 -or $exitCode -eq 931 -or $exitCode -eq 3010) {
                Write-Host "[OK] $item installed at $installTime" -ForegroundColor Green
                Add-InstallationRecord -Software $item -Status "INSTALLED"
            }
            else {
                Write-Host "[!!] $item completed with exit code $exitCode at $installTime" -ForegroundColor Yellow
                Add-InstallationRecord -Software $item -Status "INSTALLED (exit code: $exitCode)"
            }
        }
        catch {
            Write-Host "[ERROR] $item failed: $($_.Exception.Message)" -ForegroundColor Red
            Add-InstallationRecord -Software $item -Status "FAILED"
        }

        Start-Sleep -Seconds 1
    }
}

# ===========================
# SUMMARY
# ===========================

function Show-Summary {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  NEXUS DEPLOYMENT SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if ($InstallationLog.Count -gt 0) {
        $InstallationLog | Select-Object Timestamp, Software, Status | Format-Table -AutoSize
    }
    else {
        Write-Host "  [!!] No installations recorded." -ForegroundColor Yellow
    }

    $successCount = ($InstallationLog | Where-Object { $_.Status -like "*INSTALLED*" } | Measure-Object).Count
    $failCount    = ($InstallationLog | Where-Object { $_.Status -like "*FAILED*" }    | Measure-Object).Count

    Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
    Write-Host "  Result: $successCount installed | $failCount failed" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
    Write-Host ""
}

# ===========================
# MAIN EXECUTION
# ===========================

# Verify the selected package manager is available
if ($PackageManager -eq "chocolatey") {
    if (-not (Test-ChocolateyAvailable)) {
        Write-Host "[ERROR] Cannot proceed: Chocolatey is unavailable." -ForegroundColor Red
        exit 1
    }
}
else {
    if (-not (Test-WingetAvailable)) {
        Write-Host "[ERROR] Cannot proceed: Winget is unavailable." -ForegroundColor Red
        exit 1
    }
}

# Resolve the correct package list
$ActiveRequired = if ($PackageManager -eq "chocolatey") { $RequiredSoftwareChoco } else { $RequiredSoftware }

# Install required packages
Install-Software -SoftwareList $ActiveRequired

# Print summary
Show-Summary

Write-Host "[OK] N.E.X.U.S. deployment complete." -ForegroundColor Cyan
Write-Host ""
