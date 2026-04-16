<#
.SYNOPSIS
    B.A.S.T.I.O.N. — Baseline Automation: Secures, Tunes, Isolates & Obliterates Negligence
    LiveConnect-Compatible Security Baseline Enforcement for PowerShell 5.1+

.DESCRIPTION
    Applies a standardized security and configuration baseline to a Windows machine.
    Covers telemetry, screensaver lock, UAC, autorun, firewall, account policy,
    password policy, Remote Desktop, and audit policy. Changes are logged to a
    timestamped CSV in the specified path.

    Designed for fully unattended execution via Kaseya VSA LiveConnect — no
    interactive prompts, no menu navigation, no Clear-Host or Read-Host calls.

    This script is a standalone member of the Technician Toolkit LiveConnect
    suite. It does not depend on any other toolkit scripts.

.USAGE
    PS C:\> .\bastion.ps1
    PS C:\> .\bastion.ps1 -Categories "1,3,5"
    PS C:\> .\bastion.ps1 -Categories A -EnableRDP -LogPath "C:\Temp"

.PARAMETERS
    -Categories   Comma-separated category numbers to apply, or 'A' for all (default: A)
                  1  = Telemetry & Privacy
                  2  = Screensaver & Display Lock
                  3  = UAC (User Account Control)
                  4  = Autorun & Autoplay
                  5  = Windows Firewall
                  6  = Guest Account
                  7  = Password Policy
                  8  = Remote Desktop
                  9  = Audit Policy
                  10 = Windows Update Behavior

    -EnableRDP    Enable Remote Desktop (with NLA). Default: disable RDP.
    -LogPath      Folder where the CSV log is saved (default: C:\Temp)

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
    [string]$Categories = "A",
    [switch]$EnableRDP,
    [string]$LogPath    = "C:\Temp"
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

$ExecutionTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logFilename   = "BASTION_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

if (-not (Test-Path $LogPath)) {
    try { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
    catch {
        Write-Host "[ERROR] Cannot create log folder '$LogPath': $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$logFullPath = Join-Path $LogPath $logFilename

Write-Host ""
Write-Host "  B.A.S.T.I.O.N. -- Baseline Automation: Secures, Tunes, Isolates & Obliterates Negligence" -ForegroundColor Cyan
Write-Host "  Technician Toolkit LiveConnect Suite  |  v1.0" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host "  Machine    : $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "  Run As     : $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Gray
Write-Host "  Time       : $ExecutionTime" -ForegroundColor Gray
Write-Host "  Categories : $Categories" -ForegroundColor Gray
Write-Host "  Enable RDP : $EnableRDP" -ForegroundColor Gray
Write-Host "  Log        : $logFullPath" -ForegroundColor Gray
Write-Host ("  " + ("─" * 62)) -ForegroundColor Cyan
Write-Host ""
Write-Host "  [!!] This script modifies registry keys and local security policy." -ForegroundColor Yellow
Write-Host "       Domain Group Policy will override local settings where applicable." -ForegroundColor Yellow
Write-Host ""

# ===========================
# ACTION LOG
# ===========================

$ActionLog = New-Object System.Collections.ArrayList

function Add-ActionRecord {
    param(
        [string]$Category,
        [string]$Setting,
        [string]$Status,
        [string]$Detail    = "",
        [string]$Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    )
    [void]$ActionLog.Add([PSCustomObject]@{
        Timestamp = $Timestamp
        Category  = $Category
        Setting   = $Setting
        Status    = $Status
        Detail    = $Detail
    })
}

# ===========================
# BASELINE HELPER
# ===========================

function Set-BaselineReg {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type     = "DWord",
        [string]$Category,
        [string]$Label
    )

    try {
        $current = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name

        if ($null -ne $current -and $current -eq $Value) {
            Write-Host "    [OK] $Label -- already set ($Value)." -ForegroundColor Gray
            Add-ActionRecord -Category $Category -Setting $Label -Status "Already Set" -Detail "Value: $Value"
            return
        }

        if (-not (Test-Path $Path)) {
            $null = New-Item -Path $Path -Force -ErrorAction Stop
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        $prev = if ($null -ne $current) { $current } else { "(not set)" }
        Write-Host "    [+] $Label -- applied. ($prev -> $Value)" -ForegroundColor Green
        Add-ActionRecord -Category $Category -Setting $Label -Status "Applied" -Detail "$prev -> $Value"
    }
    catch {
        Write-Host "    [-] $Label -- failed: $_" -ForegroundColor Red
        Add-ActionRecord -Category $Category -Setting $Label -Status "Failed" -Detail $_
    }
}

# ===========================
# BASELINE CATEGORIES
# ===========================

function Apply-Telemetry {
    Write-Host "  [*] Applying telemetry & privacy settings..." -ForegroundColor Magenta

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "AllowTelemetry" -Value 1 `
        -Category "Telemetry" -Label "Windows Telemetry (set to Security/minimal)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" `
        -Name "DisableEnterpriseAuthProxy" -Value 1 `
        -Category "Telemetry" -Label "Disable enterprise auth proxy for telemetry"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" `
        -Name "DisabledByGroupPolicy" -Value 1 `
        -Category "Telemetry" -Label "Disable advertising ID"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" `
        -Name "RestrictImplicitInkCollection" -Value 1 `
        -Category "Telemetry" -Label "Restrict ink & typing personalization"

    Write-Host ""
}

function Apply-ScreensaverLock {
    param([int]$TimeoutSeconds = 600)

    Write-Host "  [*] Applying screensaver & display lock settings..." -ForegroundColor Magenta
    Write-Host "  [!!] Screensaver settings apply to the currently logged-on user profile." -ForegroundColor Yellow

    Set-BaselineReg `
        -Path "HKCU:\Control Panel\Desktop" `
        -Name "ScreenSaveActive" -Value "1" -Type "String" `
        -Category "Screensaver" -Label "Enable screensaver"

    Set-BaselineReg `
        -Path "HKCU:\Control Panel\Desktop" `
        -Name "ScreenSaverIsSecure" -Value "1" -Type "String" `
        -Category "Screensaver" -Label "Require password on screensaver resume"

    Set-BaselineReg `
        -Path "HKCU:\Control Panel\Desktop" `
        -Name "ScreenSaveTimeOut" -Value "$TimeoutSeconds" -Type "String" `
        -Category "Screensaver" -Label "Screensaver timeout ($($TimeoutSeconds / 60) min)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "InactivityTimeoutSecs" -Value $TimeoutSeconds `
        -Category "Screensaver" -Label "Machine inactivity lock timeout ($($TimeoutSeconds / 60) min)"

    Write-Host ""
}

function Apply-UAC {
    Write-Host "  [*] Applying UAC settings..." -ForegroundColor Magenta

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 1 `
        -Category "UAC" -Label "Enable UAC (User Account Control)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorAdmin" -Value 2 `
        -Category "UAC" -Label "UAC prompt for admins (Always Notify)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "ConsentPromptBehaviorUser" -Value 3 `
        -Category "UAC" -Label "UAC prompt for standard users (require credentials)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "PromptOnSecureDesktop" -Value 1 `
        -Category "UAC" -Label "Show UAC prompt on secure desktop"

    Write-Host ""
}

function Apply-Autorun {
    Write-Host "  [*] Applying autorun & autoplay settings..." -ForegroundColor Magenta

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "NoDriveTypeAutoRun" -Value 255 `
        -Category "Autorun" -Label "Disable AutoRun for all drives (machine)"

    Set-BaselineReg `
        -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -Name "NoDriveTypeAutoRun" -Value 255 `
        -Category "Autorun" -Label "Disable AutoRun for all drives (user)"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" `
        -Name "NoAutoplayfornonVolume" -Value 1 `
        -Category "Autorun" -Label "Disable AutoPlay for non-volume devices"

    Write-Host ""
}

function Apply-Firewall {
    Write-Host "  [*] Applying Windows Firewall settings..." -ForegroundColor Magenta

    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction Stop
        Write-Host "    [+] Windows Firewall enabled on all profiles." -ForegroundColor Green
        Add-ActionRecord -Category "Firewall" -Setting "Enable all firewall profiles" -Status "Applied"
    }
    catch {
        Write-Host "    [-] Failed to configure firewall: $_" -ForegroundColor Red
        Add-ActionRecord -Category "Firewall" -Setting "Enable all firewall profiles" -Status "Failed" -Detail $_
    }

    try {
        Set-NetFirewallProfile -Profile Public -DefaultInboundAction Block -ErrorAction Stop
        Write-Host "    [+] Public profile -- inbound connections blocked by default." -ForegroundColor Green
        Add-ActionRecord -Category "Firewall" -Setting "Block inbound on Public profile" -Status "Applied"
    }
    catch {
        Write-Host "    [-] Failed to set Public profile inbound policy: $_" -ForegroundColor Red
        Add-ActionRecord -Category "Firewall" -Setting "Block inbound on Public profile" -Status "Failed" -Detail $_
    }

    Write-Host ""
}

function Apply-GuestAccount {
    Write-Host "  [*] Applying guest account settings..." -ForegroundColor Magenta

    try {
        $guest = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
        if ($guest) {
            if ($guest.Enabled) {
                Disable-LocalUser -Name "Guest" -ErrorAction Stop
                Write-Host "    [+] Guest account disabled." -ForegroundColor Green
                Add-ActionRecord -Category "Accounts" -Setting "Disable Guest account" -Status "Applied"
            } else {
                Write-Host "    [OK] Guest account already disabled." -ForegroundColor Gray
                Add-ActionRecord -Category "Accounts" -Setting "Disable Guest account" -Status "Already Set"
            }
        } else {
            Write-Host "    [OK] Guest account not present." -ForegroundColor Gray
            Add-ActionRecord -Category "Accounts" -Setting "Disable Guest account" -Status "Not Present"
        }
    }
    catch {
        Write-Host "    [-] Failed to disable Guest account: $_" -ForegroundColor Red
        Add-ActionRecord -Category "Accounts" -Setting "Disable Guest account" -Status "Failed" -Detail $_
    }

    Write-Host ""
}

function Apply-PasswordPolicy {
    Write-Host "  [*] Applying local password policy..." -ForegroundColor Magenta
    Write-Host "  [!!] These settings apply to local accounts only. Domain policy takes precedence." -ForegroundColor Yellow

    $policies = @(
        @{ Args = "/minpwlen:8";         Label = "Minimum password length (8 characters)" },
        @{ Args = "/maxpwage:90";        Label = "Maximum password age (90 days)" },
        @{ Args = "/minpwage:1";         Label = "Minimum password age (1 day)" },
        @{ Args = "/uniquepw:5";         Label = "Password history (remember 5)" },
        @{ Args = "/lockoutthreshold:5"; Label = "Account lockout threshold (5 attempts)" },
        @{ Args = "/lockoutduration:30"; Label = "Account lockout duration (30 minutes)" }
    )

    foreach ($policy in $policies) {
        try {
            & net accounts $policy.Args.Split(' ') 2>&1 | Out-Null
            Write-Host "    [+] $($policy.Label) -- applied." -ForegroundColor Green
            Add-ActionRecord -Category "Password Policy" -Setting $policy.Label -Status "Applied"
        }
        catch {
            Write-Host "    [-] $($policy.Label) -- failed: $_" -ForegroundColor Red
            Add-ActionRecord -Category "Password Policy" -Setting $policy.Label -Status "Failed" -Detail $_
        }
    }

    Write-Host ""
}

function Apply-RemoteDesktop {
    Write-Host "  [*] Configuring Remote Desktop..." -ForegroundColor Magenta

    # Driven entirely by the -EnableRDP parameter — no prompts
    $rdpValue = if ($EnableRDP) { 0 } else { 1 }
    $rdpLabel = if ($EnableRDP) { "Enable" } else { "Disable" }

    Write-Host "  [*] Remote Desktop action: $rdpLabel" -ForegroundColor Gray

    Set-BaselineReg `
        -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
        -Name "fDenyTSConnections" -Value $rdpValue `
        -Category "Remote Desktop" -Label "$rdpLabel Remote Desktop"

    if ($EnableRDP) {
        Set-BaselineReg `
            -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
            -Name "UserAuthentication" -Value 1 `
            -Category "Remote Desktop" -Label "Require Network Level Authentication (NLA)"

        try {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction Stop
            Write-Host "    [+] Remote Desktop firewall rules enabled." -ForegroundColor Green
            Add-ActionRecord -Category "Remote Desktop" -Setting "Enable RDP firewall rules" -Status "Applied"
        }
        catch {
            Write-Host "    [!!] Could not update RDP firewall rules: $_" -ForegroundColor Yellow
        }
    } else {
        try {
            Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            Add-ActionRecord -Category "Remote Desktop" -Setting "Disable RDP firewall rules" -Status "Applied"
        }
        catch { }
    }

    Write-Host ""
}

function Apply-AuditPolicy {
    Write-Host "  [*] Applying audit policy..." -ForegroundColor Magenta

    $auditSettings = @(
        @{ Args = '/subcategory:"Logon" /success:enable /failure:enable';                         Label = "Logon events" },
        @{ Args = '/subcategory:"Logoff" /success:enable';                                        Label = "Logoff events" },
        @{ Args = '/subcategory:"Account Lockout" /failure:enable';                               Label = "Account lockout failures" },
        @{ Args = '/subcategory:"Audit Policy Change" /success:enable /failure:enable';           Label = "Audit policy changes" },
        @{ Args = '/subcategory:"User Account Management" /success:enable /failure:enable';       Label = "User account management" }
    )

    foreach ($audit in $auditSettings) {
        try {
            $result = & auditpol $audit.Args.Split(' ') 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [+] $($audit.Label) -- enabled." -ForegroundColor Green
                Add-ActionRecord -Category "Audit Policy" -Setting $audit.Label -Status "Applied"
            } else {
                Write-Host "    [!!] $($audit.Label) -- may require domain policy override." -ForegroundColor Yellow
                Add-ActionRecord -Category "Audit Policy" -Setting $audit.Label -Status "Skipped" -Detail "May be overridden by domain policy"
            }
        }
        catch {
            Write-Host "    [-] $($audit.Label) -- failed: $_" -ForegroundColor Red
            Add-ActionRecord -Category "Audit Policy" -Setting $audit.Label -Status "Failed" -Detail $_
        }
    }

    Write-Host ""
}

function Apply-WindowsUpdatePolicy {
    Write-Host "  [*] Applying Windows Update behavior..." -ForegroundColor Magenta

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" `
        -Name "ExcludeWUDriversInQualityUpdate" -Value 1 `
        -Category "Windows Update" -Label "Exclude driver updates from Windows Update"

    Set-BaselineReg `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 `
        -Category "Windows Update" -Label "No auto-reboot while users are logged on"

    Write-Host ""
}

# ===========================
# CATEGORY REGISTRY
# ===========================

$categoryMap = [ordered]@{
    "1"  = @{ Label = "Telemetry & Privacy";        Fn = { Apply-Telemetry } }
    "2"  = @{ Label = "Screensaver & Display Lock"; Fn = { Apply-ScreensaverLock } }
    "3"  = @{ Label = "UAC (User Account Control)"; Fn = { Apply-UAC } }
    "4"  = @{ Label = "Autorun & Autoplay";         Fn = { Apply-Autorun } }
    "5"  = @{ Label = "Windows Firewall";           Fn = { Apply-Firewall } }
    "6"  = @{ Label = "Guest Account";              Fn = { Apply-GuestAccount } }
    "7"  = @{ Label = "Password Policy";            Fn = { Apply-PasswordPolicy } }
    "8"  = @{ Label = "Remote Desktop";             Fn = { Apply-RemoteDesktop } }
    "9"  = @{ Label = "Audit Policy";               Fn = { Apply-AuditPolicy } }
    "10" = @{ Label = "Windows Update Behavior";    Fn = { Apply-WindowsUpdatePolicy } }
}

# Resolve selected keys
$rawInput    = $Categories.Trim().ToUpper()
$selectedKeys = @()

if ($rawInput -eq "A") {
    $selectedKeys = $categoryMap.Keys
} else {
    $selectedKeys = $rawInput -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object   { $categoryMap.ContainsKey($_) }
}

if ($selectedKeys.Count -eq 0) {
    Write-Host "[ERROR] No valid categories selected from input: '$Categories'" -ForegroundColor Red
    Write-Host "        Valid values: 1-10 (comma-separated) or A for all." -ForegroundColor Yellow
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  APPLYING BASELINE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($key in $selectedKeys) {
    $cat = $categoryMap[$key]
    Write-Host ("  " + ("─" * 40)) -ForegroundColor Cyan
    Write-Host "  $($cat.Label)" -ForegroundColor Cyan
    Write-Host ("  " + ("─" * 40)) -ForegroundColor Cyan
    & $cat.Fn
}

# ===========================
# SAVE LOG
# ===========================

try {
    $ActionLog | Export-Csv -Path $logFullPath -NoTypeInformation -Encoding UTF8
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
Write-Host "  BASTION DEPLOYMENT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$applied    = ($ActionLog | Where-Object { $_.Status -eq "Applied"     } | Measure-Object).Count
$alreadySet = ($ActionLog | Where-Object { $_.Status -eq "Already Set" } | Measure-Object).Count
$skipped    = ($ActionLog | Where-Object { $_.Status -eq "Skipped"     } | Measure-Object).Count
$failed     = ($ActionLog | Where-Object { $_.Status -eq "Failed"      } | Measure-Object).Count

Write-Host "  Applied     : $applied" -ForegroundColor Green
Write-Host "  Already Set : $alreadySet" -ForegroundColor Gray
Write-Host "  Skipped     : $skipped" -ForegroundColor Yellow
Write-Host "  Failed      : $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host ""
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host "  LOG PATH: $logFullPath" -ForegroundColor Cyan
Write-Host ("  " + ("─" * 55)) -ForegroundColor Cyan
Write-Host ""
Write-Host "[OK] B.A.S.T.I.O.N. baseline complete." -ForegroundColor Cyan
Write-Host ""
