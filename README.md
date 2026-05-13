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

### Deployment, baseline & diagnostics

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **nexus.ps1** | **N.E.X.U.S.** — Network-Executed Xpress Unattended Setup | Required software deployment via winget or Chocolatey | C.O.N.J.U.R.E. |
| **probe.ps1** | **P.R.O.B.E.** — Performs Rapid Operating-system Baseline Evaluation | System diagnostics and HTML report generation | O.R.A.C.L.E. |
| **audit.ps1** | **A.U.D.I.T.** — Automated User Detection, Inspection & Triage | Local user account audit and HTML report | W.A.R.D. |
| **bastion.ps1** | **B.A.S.T.I.O.N.** — Baseline Automation: Secures, Tunes, Isolates & Obliterates Negligence | Security baseline enforcement | S.I.G.I.L. |
| **renew.ps1** | **R.E.N.E.W.** — Remotely Enacted Non-interactive Engine for Windows-updates | Windows Update installation | R.E.S.T.O.R.A.T.I.O.N. |

### Security & health audits

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **snare.ps1** | **S.N.A.R.E.** — Surveys Native Autoruns & Records Entries | Persistence/autoruns audit (Run keys, startup folders, services, scheduled tasks, WMI subscriptions, IFEO, Winlogon) with signature & target-existence enrichment | T.A.L.O.N. |
| **seal.ps1** | **S.E.A.L.** — Secure Element Audit Log | TPM presence/spec/owner audit, BitLocker dependency cross-reference, EK readiness, Windows 11 / Autopilot readiness verdict | T.O.T.E.M. |
| **aegis.ps1** | **A.E.G.I.S.** — Antivirus Endpoint Guard Inspection Snapshot | Microsoft Defender posture: real-time, tamper, signatures, threats, ASR, exclusions, third-party AV, service health, recent events | P.A.L.A.D.I.N. |
| **pulse.ps1** | **P.U.L.S.E.** — Physical-disk Usage, Lifespan & SMART Evaluation | Physical-disk health, SMART failure prediction, serial/firmware, volume capacity | A.U.G.U.R. |
| **mortar.ps1** | **M.O.R.T.A.R.** — Motherboard, Onboard ROM & TPM/UEFI Audit Report | BIOS/UEFI state, Secure Boot, vendor firmware-update channels, optional WU driver/firmware scan | A.N.V.I.L. |
| **spark.ps1** | **S.P.A.R.K.** — System Power Audit Reporting Kit | Battery health (design vs full charge, cycle count), capacity history, runtime estimates, AC/DC usage — runs powercfg /batteryreport | P.Y.R.E. |

### Network & identity audits

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **signal.ps1** | **S.I.G.N.A.L.** — Surveys Identified Guard Networks And Logs | Saved Wi-Fi profile audit: authentication, cipher, autoSwitch, hidden SSID, MAC randomization. Flags open / weak / auto-connect entries. Keys masked unless `-IncludeKey`. | B.E.A.C.O.N. |
| **tunnel.ps1** | **T.U.N.N.E.L.** — Tracks Unattended Network Negotiation Endpoints & Logging | Built-in Windows VPN connections, Always-On triggers, NRPT, tunnel interfaces, third-party VPN-client service detection (12+ vendors) | P.O.R.T.A.L. |
| **relic.ps1** | **R.E.L.I.C.** — Reports Expiry of Local Identity Certificates | Local cert store audit (My/CA/Root/TrustedPublisher) + optional SSL/TLS remote-host expiry check | A.R.T.I.F.A.C.T. |
| **torch.ps1** | **T.O.R.C.H.** — Test Of Reachable Connected Hosts | Parallel /24 ping sweep, DNS reverse lookup, ARP MAC join, TCP port scan (10 common ports), CSV + HTML | L.A.N.T.E.R.N. |

### Data & migration prep

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **anchor.ps1** | **A.N.C.H.O.R.** — Audits Native Cloud Hookups & OneDrive Readiness | OneDrive client install + sign-in + Known Folder Move redirection + content volume + sync errors | T.E.T.H.E.R. |
| **vault.ps1** | **V.A.U.L.T.** — Visits Aged Unindexed Long-forgotten Troves | Outlook PST/OST discovery with profile cross-reference, orphan / oversize (50 GB) / stale flagging | E.X.H.U.M.E. |
| **vision.ps1** | **V.I.S.I.O.N.** — Verifies Inventory, Status & Operational Numbers | One-shot 5-section unified report: system overview, users, disk space, disk health, services & failed tasks | S.C.R.Y.E.R. |

### Cleanup & maintenance

| Script | Acronym | Purpose | Counterpart |
|--------|---------|---------|-------------|
| **verge.ps1** | **V.E.R.G.E.** — Volume Examination & Resource Gauge Evaluator | Read-only disk health + volume space audit + stale user-profile detection | T.H.R.E.S.H.O.L.D. (audit subset) |
| **purge.ps1** | **P.U.R.G.E.** — PowerShell Unified Reclamation & Garbage Elimination | Disk cleanup (user/system temp, WU cache, recycle bin, browser caches) with categories + WhatIf | C.L.E.A.N.S.E. |
| **sentry.ps1** | **S.E.N.T.R.Y.** — Services, Events 'N Tasks Reporting Yield | Critical services, scheduled-task health, recent System/Application errors | G.A.R.G.O.Y.L.E. (audit-only) |

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

# S.N.A.R.E. — Persistence / autoruns audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\snare.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/snare.ps1 -OutFile $f; & $f

# S.E.A.L. — TPM health & BitLocker dependency
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\seal.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/seal.ps1 -OutFile $f; & $f

# A.E.G.I.S. — AV / Defender posture
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\aegis.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/aegis.ps1 -OutFile $f; & $f

# P.U.L.S.E. — Disk health & SMART
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\pulse.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/pulse.ps1 -OutFile $f; & $f

# M.O.R.T.A.R. — BIOS / UEFI / firmware audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\mortar.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/mortar.ps1 -OutFile $f; & $f

# S.P.A.R.K. — Battery health (laptops only)
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\spark.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/spark.ps1 -OutFile $f; & $f

# V.E.R.G.E. — Disk space + stale profile audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\verge.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/verge.ps1 -OutFile $f; & $f

# P.U.R.G.E. — Disk cleanup
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\purge.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/purge.ps1 -OutFile $f; & $f

# S.E.N.T.R.Y. — Service / task / event audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\sentry.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/sentry.ps1 -OutFile $f; & $f

# S.I.G.N.A.L. — Wi-Fi profile audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\signal.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/signal.ps1 -OutFile $f; & $f

# T.U.N.N.E.L. — VPN / Always-On audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\tunnel.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/tunnel.ps1 -OutFile $f; & $f

# R.E.L.I.C. — Certificate / SSL expiry audit
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\relic.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/relic.ps1 -OutFile $f; & $f

# T.O.R.C.H. — Network discovery & port scan
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\torch.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/torch.ps1 -OutFile $f; & $f

# A.N.C.H.O.R. — OneDrive KFM readiness
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\anchor.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/anchor.ps1 -OutFile $f; & $f

# V.A.U.L.T. — Outlook PST / OST discovery
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\vault.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/vault.ps1 -OutFile $f; & $f

# V.I.S.I.O.N. — Unified 5-section diagnostic
Set-ExecutionPolicy Bypass -Scope Process -Force; $f="$env:TEMP\vision.ps1"; irm https://raw.githubusercontent.com/CursedTechnocrat/TechnicianToolkit-LiveConnect/main/vision.ps1 -OutFile $f; & $f
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

### S.N.A.R.E. — Persistence / Autoruns Audit

Sweeps Run/RunOnce keys (HKCU + HKLM, including Wow6432), Startup folders, auto-start Services, non-Microsoft Scheduled Tasks, WMI event subscriptions, Image File Execution Options debugger hooks, and Winlogon (Shell, Userinit, AppInit_DLLs). Each entry is enriched with Authenticode signature status and target-on-disk existence.

```powershell
.\snare.ps1
.\snare.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `SNARE_<yyyyMMdd_HHmmss>.html`. Read-only — no state-changing actions.

---

### S.E.A.L. — TPM Health Audit

Reads the TPM via `Get-Tpm` (presence, spec, manufacturer, ownership, ready state), cross-references against BitLocker volumes to identify which protectors actually depend on the TPM, and verifies the Endorsement Key is readable. Produces a red / yellow / green readiness verdict suitable for Windows 11 / BitLocker / Autopilot gating.

```powershell
.\seal.ps1
.\seal.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `SEAL_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### A.E.G.I.S. — AV / Defender Posture

Reads Microsoft Defender state (`Get-MpComputerStatus` / `Get-MpPreference`), threat history, recent detections, registered third-party AV products (SecurityCenter2), Defender service health, and Defender Operational events from the last N days.

```powershell
.\aegis.ps1
.\aegis.ps1 -ReportPath "C:\Temp"
.\aegis.ps1 -EventDays 14 -SignatureMaxAgeDays 3
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-EventDays` | `int` | `7` | Look-back window for Defender Operational events (1-90) |
| `-SignatureMaxAgeDays` | `int` | `7` | Yellow threshold for AV signature age (red = 2x) |

**Output:** `AEGIS_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### P.U.L.S.E. — Disk Health & SMART

Inspects every physical disk: health status, SMART failure prediction (via `MSStorageDriver_FailurePredictStatus`), serial, firmware, bus/media type. Cross-checks volume health and capacity.

```powershell
.\pulse.ps1
.\pulse.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `PULSE_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### M.O.R.T.A.R. — BIOS / UEFI / Firmware Audit

System identity (manufacturer, model, serial, UUID), BIOS version & release date, UEFI / Legacy boot mode, Secure Boot state, and vendor-channel firmware-update tooling presence (Dell Command Update, HP HPIA / HPSA, Lenovo Vantage / System Update, Surface UEFI Configurator).

```powershell
.\mortar.ps1
.\mortar.ps1 -ReportPath "C:\Temp"
.\mortar.ps1 -ScanWindowsUpdate    # add WU driver/firmware scan (requires PSWindowsUpdate already installed)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-ScanWindowsUpdate` | `switch` | off | Scan Windows Update for pending driver/firmware updates. Never auto-installs PSWindowsUpdate. |

**Output:** `MORTAR_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### S.P.A.R.K. — Battery Health (Laptops)

Reads ROOT\WMI battery classes for design vs full-charge capacity, cycle count, voltage and chemistry. Runs `powercfg /batteryreport` to enrich with serial, manufacture date, capacity history, runtime estimates at full charge vs design, and AC/DC usage totals. The original Microsoft-formatted HTML and the parsed XML are saved alongside the SPARK report. Skips powercfg cleanly when no battery is present (desktops/servers/VMs).

```powershell
.\spark.ps1
.\spark.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report (and powercfg files) are saved |

**Output:**
- `SPARK_<yyyyMMdd_HHmmss>.html` — main report
- `SPARK_powercfg_<yyyyMMdd_HHmmss>.xml` — parsed powercfg data
- `SPARK_powercfg_<yyyyMMdd_HHmmss>.html` — Microsoft-formatted battery report (when available)

Thresholds: capacity ≥ 80% healthy, 60-80% plan replacement, < 60% replace now. Cycles < 300 healthy, 300-500 plan replacement, ≥ 500 replace now.

---

### V.E.R.G.E. — Disk Space & Stale Profile Audit

Read-only sibling to P.U.R.G.E. Inspects physical-disk health, per-volume capacity with low-space flags (Warning < 15% free, Critical < 5%), and detects user profiles under `C:\Users` that haven't been modified in N days. Includes progress bars in the HTML.

```powershell
.\verge.ps1
.\verge.ps1 -ReportPath "C:\Temp"
.\verge.ps1 -StaleProfileDays 60
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-StaleProfileDays` | `int` | `90` | Days of profile inactivity that flag a user as stale |

**Output:** `VERGE_<yyyyMMdd_HHmmss>.html`. Read-only — no cleanup is performed.

---

### P.U.R.G.E. — Disk Cleanup

Cleans user/system temp folders, the Windows Update download cache (stops/restarts `wuauserv`), the Recycle Bin, and browser caches (Chrome, Edge, Firefox — all user profiles). Categories are selected by number; `WhatIf` previews without deleting. A CSV of what was reclaimed is written.

```powershell
.\purge.ps1                               # All categories
.\purge.ps1 -Categories "1,3,5"           # User temp + WU cache + browser caches
.\purge.ps1 -WhatIf                       # Preview only
.\purge.ps1 -LogPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Categories` | `string` | `A` | Categories to clean: comma-separated numbers or `A` for all |
| `-WhatIf` | `switch` | off | Scan only; do not delete |
| `-LogPath` | `string` | `C:\Temp` | Folder where the CSV log is saved |

**Categories**

| # | Category |
|---|----------|
| 1 | User Temp Folders (`%TEMP%`, `%LOCALAPPDATA%\Temp`) |
| 2 | System Temp (`C:\Windows\Temp`) |
| 3 | Windows Update Cache (`C:\Windows\SoftwareDistribution\Download`) |
| 4 | Recycle Bin |
| 5 | Browser Caches (Chrome, Edge, Firefox — every user profile) |

**Output:** `PURGE_<yyyyMMdd_HHmmss>.csv`.

---

### S.E.N.T.R.Y. — Service / Task / Event Audit

Reports on 15 critical Windows services, every scheduled task (flags non-Microsoft Failed / Disabled / Stale entries), and System + Application event-log errors from the last N hours. Includes a top-sources summary.

```powershell
.\sentry.ps1
.\sentry.ps1 -ReportPath "C:\Temp"
.\sentry.ps1 -EventHours 48
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-EventHours` | `int` | `24` | Look-back window for System/Application errors (1-168) |

**Output:** `SENTRY_<yyyyMMdd_HHmmss>.html`. Audit-only — does NOT restart services.

---

### S.I.G.N.A.L. — Wi-Fi Profile Audit

Exports every saved WLAN profile via `netsh wlan export profile ... key=clear`, parses the XML, and reports authentication / cipher tier, connection mode, autoSwitch, hidden-SSID, MAC randomization, and 802.1X for each profile. Filtered tables for open / weak and auto-connecting networks.

```powershell
.\signal.ps1
.\signal.ps1 -ReportPath "C:\Temp"
.\signal.ps1 -IncludeKey        # render cleartext PSKs (technician-managed audits only)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-IncludeKey` | `switch` | off | Render cleartext pre-shared keys (default: masked) |

**Output:** `SIGNAL_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### T.U.N.N.E.L. — VPN / Always-On VPN Audit

Enumerates built-in Windows VPN connections at User and AllUser scope, surfaces Always-On app/DNS triggers, dumps NRPT, lists active tunnel interfaces, and detects 17+ third-party VPN client services (Cisco, GlobalProtect, Pulse, OpenVPN, WireGuard, Tailscale, ZeroTier, Cloudflare WARP, NordVPN, ProtonVPN, F5, Citrix).

```powershell
.\tunnel.ps1
.\tunnel.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `TUNNEL_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### R.E.L.I.C. — Certificate / SSL Expiry Audit

Audits LocalMachine certificate stores (My, CA, Root, TrustedPublisher) for expired and expiring-soon certificates. Optionally connects to remote hosts and checks the presented SSL/TLS certificate's expiry. Thresholds: < 30 days Critical, < 90 days Warning.

```powershell
.\relic.ps1
.\relic.ps1 -Targets "mail.contoso.com, gw.contoso.com:8443"
.\relic.ps1 -Targets "C:\Temp\hosts.txt"   # one host[:port] per line; # comments OK
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-Targets` | `string` | `""` | Comma-separated `hostname[:port]` list, or a path to a text file with one per line. Default port: 443. |

**Output:** `RELIC_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### T.O.R.C.H. — Network Discovery & Port Scan

Parallel ping sweep of the local `/24` subnet (50 concurrent runspaces, 15-second timeout), DNS reverse lookup, ARP MAC join, and TCP port scan of 10 common ports (21, 22, 23, 80, 443, 445, 3389, 5985, 8080, 8443). Saves a CSV alongside the HTML.

```powershell
.\torch.ps1
.\torch.ps1 -ReportPath "C:\Temp"
.\torch.ps1 -SkipPortScan
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML and CSV are saved |
| `-SkipPortScan` | `switch` | off | Skip the TCP port scan stage (sweep only) |

**Output:** `TORCH_<yyyyMMdd_HHmmss>.html` and `TORCH_<yyyyMMdd_HHmmss>.csv`. Read-only.

---

### A.N.C.H.O.R. — OneDrive KFM Pre-Migration Readiness

Audits OneDrive readiness for the **running user's HKCU hive**: client install/running state, signed-in Business and Personal accounts, Known Folder Move redirection (Desktop / Documents / Pictures), per-folder content volume, and OneDrive/User-Profile-Service errors from the last 7 days. Verdict gates a re-image or laptop swap.

```powershell
.\anchor.ps1
.\anchor.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `ANCHOR_<yyyyMMdd_HHmmss>.html`. Read-only.

> **Note:** Reads `HKCU:\Software\Microsoft\OneDrive\Accounts` for the running session's user. To audit a different user's OneDrive state, run the script in that user's session.

---

### V.A.U.L.T. — Outlook PST / OST Discovery

Scans the requested drives for `.pst` (and optionally `.ost`) files outside standard system / Program Files directories. Reads HKCU Outlook profiles (16.0 / 15.0 / 14.0 hives) and cross-references discovered files to identify orphans. Flags files ≥ 50 GB (Exchange Online Import hard cap), 10-50 GB (slow lane), and stale > 365 days since last access.

```powershell
.\vault.ps1                                # All fixed drives, PST only
.\vault.ps1 -ScanDrives "C:,D:" -IncludeOst
.\vault.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |
| `-ScanDrives` | `string` | `""` (all fixed) | Comma-separated drive letters, e.g. `"C:,D:"` |
| `-IncludeOst` | `switch` | off | Also enumerate `.ost` files (default: PST only) |

**Output:** `VAULT_<yyyyMMdd_HHmmss>.html`. Read-only.

---

### V.I.S.I.O.N. — Unified 5-Section Diagnostic

Single HTML report that combines an entire technician handoff in one pass: system overview (OS, hardware, RAM, uptime, PS version), local users with admin / last-logon, per-volume disk-space with progress bars, physical-disk health + SMART (temp & wear via StorageReliabilityCounter), and a services & failed-tasks roll-up.

```powershell
.\vision.ps1
.\vision.ps1 -ReportPath "C:\Temp"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ReportPath` | `string` | `C:\Temp` | Folder where the HTML report is saved |

**Output:** `VISION_<yyyyMMdd_HHmmss>.html`. Read-only.

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
| PSWindowsUpdate module | `renew.ps1` (auto-installed if missing); `mortar.ps1` only when `-ScanWindowsUpdate` is passed (never auto-installed) |
| `Get-Tpm` / TrustedPlatformModule module | `seal.ps1` (in-box on Windows 10/11) |
| Defender PowerShell module | `aegis.ps1` (in-box; collector failures are reported gracefully on Server Core / Defender-removed builds) |
| Battery hardware | `spark.ps1` (gracefully reports "no battery" on desktops/servers/VMs) |

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
| `snare.ps1` | `talon.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
| `seal.ps1` | `totem.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
| `aegis.ps1` | `paladin.ps1` | No banner, no "press Enter" pause, no browser auto-open — event window & signature thresholds passed as parameters |
| `pulse.ps1` | `augur.ps1` | No banner, no "open report?" prompt — report path passed as parameter |
| `mortar.ps1` | `anvil.ps1` | No banner, no "press Enter" pause; Windows Update driver scan is opt-in via `-ScanWindowsUpdate` and never auto-installs PSWindowsUpdate |
| `spark.ps1` | `pyre.ps1` | No banner, no "press Enter" pause, no browser auto-open; powercfg XML+HTML are saved alongside the SPARK report |
| `verge.ps1` | `threshold.ps1` (audit subset) | No interactive menu, no cleanup actions (use `purge.ps1`); read-only disk + volume + stale-profile audit only |
| `purge.ps1` | `cleanse.ps1` | No interactive category menu, no Y/N confirmations — categories and `-WhatIf` passed as parameters; CSV log of cleanup written |
| `sentry.ps1` | `gargoyle.ps1` (audit subset) | No interactive menu, no remote target, no service-restart prompts — read-only audit only |
| `signal.ps1` | `beacon.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
| `tunnel.ps1` | `portal.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
| `relic.ps1` | `artifact.ps1` | No interactive menu, no SSL-target prompt — `-Targets` passed as parameter (CSV or file path) |
| `torch.ps1` | `lantern.ps1` | No interactive menu, port scan is on by default (controlled by `-SkipPortScan`), CSV always written alongside HTML |
| `anchor.ps1` | `tether.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
| `vault.ps1` | `exhume.ps1` | No banner, no "press Enter" pause — `-ScanDrives` accepts a comma-separated string instead of a string array |
| `vision.ps1` | `scryer.ps1` | No banner, no "press Enter" pause, no browser auto-open — report path passed as parameter |
