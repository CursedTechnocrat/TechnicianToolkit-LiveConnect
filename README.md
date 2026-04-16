# Technician Toolkit — LiveConnect Suite

> Standalone, parameter-driven PowerShell scripts built for Kaseya VSA LiveConnect. No menus, no prompts, no interactive input — drop them into a LiveConnect terminal and go.

---

## Which Toolkit Should I Use?

> **Working at the machine or in a full RDP session?** Use the main toolkit instead:
> ### [TechnicianToolkit →](https://github.com/CursedTechnocrat/TechnicianToolkit)

| Situation | Use |
|-----------|-----|
| Running through Kaseya VSA LiveConnect | **This repo** — TechnicianToolkit-LiveConnect |
| Sitting at the machine or in a full RDP session | **[TechnicianToolkit](https://github.com/CursedTechnocrat/TechnicianToolkit)** |
| Need fire-and-forget with parameter-only input | **This repo** — all inputs are parameters, no prompts |
| Need a guided, menu-driven workflow with confirmations | **[TechnicianToolkit](https://github.com/CursedTechnocrat/TechnicianToolkit)** |
| Need COVENANT, PHANTOM, CIPHER, ARCHIVE, SPECTER, or RUNEPRESS | **[TechnicianToolkit](https://github.com/CursedTechnocrat/TechnicianToolkit)** — these tools are interactive by nature and have no LiveConnect counterpart |

### Why are these separate?

The main Technician Toolkit is built around interactive menus, `Read-Host` prompts, `ReadKey` pauses, and `Clear-Host` calls — features that make it guided and approachable when a technician is present. LiveConnect's PowerShell shell cannot handle any of those. The session hangs or errors out immediately when any interactive call is encountered.

Every script in this repo is written from scratch to run entirely from parameters. All output is plain status lines. Report and log file paths are printed clearly at the end of each run so you can retrieve them through LiveConnect's file transfer or a mapped share.

---

## Scripts

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **nexus.ps1** | **N.E.X.U.S.** — Network-Executed Xpress Unattended Setup | Required software deployment via winget or Chocolatey | C.O.N.J.U.R.E. |
| **probe.ps1** | **P.R.O.B.E.** — Performs Rapid Operating-system Baseline Evaluation | System diagnostics and HTML report generation | O.R.A.C.L.E. |
| **audit.ps1** | **A.U.D.I.T.** — Automated User Detection, Inspection & Triage | Local user account audit and HTML report | W.A.R.D. |
| **bastion.ps1** | **B.A.S.T.I.O.N.** — Baseline Automation: Secures, Tunes, Isolates & Obliterates Negligence | Security baseline enforcement | S.I.G.I.L. |
| **renew.ps1** | **R.E.N.E.W.** — Remotely Enacted Non-interactive Engine for Windows-updates | Windows Update installation | R.E.S.T.O.R.A.T.I.O.N. |

---

## Quick Launch

Run any script directly from GitHub without cloning — downloads to `%TEMP%` and executes immediately. Append parameters after `& $f` as needed (see [Usage](#usage) for each script's parameters).

```powershell
# A.U.D.I.T. — User account audit and HTML report
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\audit.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/audit.ps1 -OutFile $f; & $f

# B.A.S.T.I.O.N. — Security baseline enforcement
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\bastion.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/bastion.ps1 -OutFile $f; & $f

# N.E.X.U.S. — Software deployment
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\nexus.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/nexus.ps1 -OutFile $f; & $f

# P.R.O.B.E. — System diagnostics and HTML report
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\probe.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/probe.ps1 -OutFile $f; & $f

# R.E.N.E.W. — Windows Update installation
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\renew.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/renew.ps1 -OutFile $f; & $f
```

> All scripts require an Administrator PowerShell session. The `-Scope Process` flag limits the execution policy bypass to the current session only — it does not permanently change system policy.

---

## Usage

### N.E.X.U.S. — Software Deployment

Installs the standard required software packages silently. No optional packages, no prompts.

```powershell
# Default (winget)
.\nexus.ps1

# Use Chocolatey instead
.\nexus.ps1 -PackageManager chocolatey
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-PackageManager` | `string` | `winget` | Package manager to use: `winget` or `chocolatey` |

**Default packages installed**

| winget ID | Chocolatey ID | Software |
|-----------|---------------|----------|
| `Microsoft.Teams` | `microsoft-teams` | Microsoft Teams |
| `Microsoft.Office` | `microsoft365apps` | Microsoft 365 |
| `7zip.7zip` | `7zip` | 7-Zip |
| `Google.Chrome` | `googlechrome` | Google Chrome |
| `Adobe.Acrobat.Reader.64-bit` | `adobereader` | Adobe Acrobat Reader |
| `Zoom.Zoom` | `zoom` | Zoom |

**Output:** Installation status table printed to console on completion. No file output.

---

### P.R.O.B.E. — System Diagnostic Report

Audits hardware, OS, network, uptime, pending updates, installed software, and recent event log errors. Saves a dark-themed HTML report to the specified folder.

```powershell
# Save report to C:\Temp (default)
.\probe.ps1

# Save report to a custom path
.\probe.ps1 -ReportPath "C:\Temp"

# Save report to a network share
.\probe.ps1 -ReportPath "\\server\share\Reports"
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `PROBE_<yyyyMMdd_HHmmss>.html` in the specified folder. Path is printed at the end of the run.

**Report sections**
- Hardware (manufacturer, model, serial, CPU, RAM, disk usage with visual bars)
- Operating system (version, build, architecture, install date, activation status)
- Network configuration (all active adapters — IP, MAC, gateway, DNS)
- System health (last boot time, uptime, battery if applicable)
- Pending Windows Updates
- Installed software list
- Recent event log errors and critical events (last 24 hours)

---

### A.U.D.I.T. — User Account Audit

Enumerates all local user accounts, checks group memberships, flags risky conditions, and saves a dark-themed HTML report.

```powershell
# Save report to C:\Temp (default)
.\audit.ps1

# Save report to a custom path
.\audit.ps1 -ReportPath "C:\Temp"

# Save report to a network share
.\audit.ps1 -ReportPath "\\server\share\Reports"
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `AUDIT_<yyyyMMdd_HHmmss>.html` in the specified folder. Path is printed at the end of the run.

**Flags applied to accounts**
- No password required
- Password never set
- Stale (no logon in 90+ days)
- Disabled

---

### B.A.S.T.I.O.N. — Security Baseline Enforcement

Applies a standardized security baseline. All ten categories run by default; pass specific numbers to target only what you need. Changes are logged to a CSV.

```powershell
# Apply all categories (default)
.\bastion.ps1

# Apply specific categories only
.\bastion.ps1 -Categories "1,3,5,7"

# Apply all, enable RDP instead of disabling it
.\bastion.ps1 -Categories A -EnableRDP

# Custom log folder
.\bastion.ps1 -LogPath "C:\Temp"
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Categories` | `string` | `A` | Categories to apply: comma-separated numbers (e.g. `"1,3,5"`) or `A` for all |
| `-EnableRDP` | `switch` | off | Enable Remote Desktop with NLA. Default behavior is to **disable** RDP. |
| `-LogPath` | `string` | `C:\Temp` | Folder where the CSV change log is saved |

**Categories**

| # | Category |
|---|----------|
| 1 | Telemetry & Privacy |
| 2 | Screensaver & Display Lock (10-minute timeout, password on resume) |
| 3 | UAC — Always Notify, secure desktop |
| 4 | Autorun & Autoplay — disabled for all drive types |
| 5 | Windows Firewall — all profiles enabled, Public profile blocks inbound |
| 6 | Guest Account — disable if present |
| 7 | Password Policy — min length 8, max age 90 days, lockout after 5 attempts |
| 8 | Remote Desktop — disable by default (use `-EnableRDP` to enable with NLA) |
| 9 | Audit Policy — logon, logoff, lockout, policy change, account management |
| 10 | Windows Update Behavior — exclude drivers, no auto-reboot with logged-on users |

**Output:** `BASTION_<yyyyMMdd_HHmmss>.csv` in the specified folder. Path is printed at the end of the run.

> **Note:** Domain Group Policy takes precedence over local settings. Screensaver settings (category 2) apply to the currently logged-on user profile.

---

### R.E.N.E.W. — Windows Update Installation

Detects and installs available Windows Updates (drivers excluded). Disables sleep for the duration and restores power settings on exit. Saves a full session transcript.

```powershell
# Install updates, do not reboot automatically
.\renew.ps1

# Install updates and reboot automatically if required
.\renew.ps1 -AutoReboot
```

**Parameters**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-AutoReboot` | `switch` | off | Reboot the machine automatically if updates require it. Default: report that a reboot is needed but do not reboot. |

**Output:** Transcript log saved to `%TEMP%\RENEW_<yyyyMMdd_HHmmss>.log`. Path is printed at the end of the run.

---

## Retrieving Output Files

After a script finishes, the output file path is printed on its own line:

```
  REPORT PATH: C:\Temp\PROBE_20260416_103045.html
```

Use LiveConnect's file transfer or a mapped share to retrieve the file from the target machine.

---

## Requirements

| Requirement | Applies To |
|-------------|------------|
| Windows PowerShell 5.1+ | All scripts |
| Administrator privileges | All scripts |
| Internet connectivity | `nexus.ps1`, `renew.ps1` |
| winget or Chocolatey | `nexus.ps1` (auto-installs Chocolatey if missing) |
| PSWindowsUpdate module | `renew.ps1` (auto-installed if missing) |

---

## Design Rules

All LiveConnect scripts follow the same pattern:

- **No `Read-Host`** — all inputs are parameters
- **No `ReadKey` or `Pause-ForKey`** — no key-wait calls of any kind
- **No `Clear-Host`** — output is never wiped mid-run
- **No ASCII banners** — header is plain `Write-Host` lines only
- **Plain status lines** — `[OK]`, `[!!]`, `[*]`, `[ERROR]` prefixes throughout
- **Report/log path printed at the end** — always easy to find and retrieve
- **Standalone** — no dependencies on other toolkit scripts

---

## Relationship to the Main Toolkit

**Main Toolkit:** https://github.com/CursedTechnocrat/TechnicianToolkit

These scripts are LiveConnect-only counterparts to tools in the main Technician Toolkit. They are not launched from GRIMOIRE and do not share code with the main scripts. Each one was written from scratch to guarantee no interactive calls are present.

| LiveConnect Script | Main Toolkit Equivalent | What's different |
|--------------------|------------------------|-----------------|
| `nexus.ps1` | `conjure.ps1` | No package manager prompt, no optional software, no status menu — required packages only |
| `probe.ps1` | `oracle.ps1` | No banner, no "open report?" prompt — report path passed as parameter |
| `audit.ps1` | `ward.ps1` | No banner, no "press Enter" pause — report path passed as parameter |
| `bastion.ps1` | `sigil.ps1` | No category selection menu, no RDP prompt — categories and RDP passed as parameters |
| `renew.ps1` | `restoration.ps1` | No countdown timer, no reboot prompt — `-AutoReboot` switch controls reboot behavior |
