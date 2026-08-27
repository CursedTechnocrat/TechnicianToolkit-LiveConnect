# Contributing to the Technician Toolkit — LiveConnect Suite

These scripts run in one of the least forgiving environments a technician deals with: a remote
shell that cannot prompt, cannot wait for a keypress, and will hang outright if a script tries.
They get written and debugged against real client endpoints, and that is where their bugs turn
up. If you hit one in the field, push the fix back — it is worth more here than in your local
copy.

Contributions are welcome from technicians at every level. A bug report that says "PULSE throws
on a VM with no physical disks" is a real contribution, patch or no patch.

## Licensing of contributions

This suite is licensed **GPL-3.0-or-later**. Contributions are accepted under that same
license — inbound matches outbound.

- **You keep the copyright in what you write.** There is no copyright assignment and no CLA.
- By opening a pull request you are licensing your contribution under GPL-3.0-or-later, so it
  can ship with the rest of the suite.
- Only submit code you have the right to license. Do not paste in a client's proprietary
  scripts, vendor sample code with restrictive terms, or code under an incompatible license.

New scripts need the standard notice header. Copy it verbatim from any existing script and
change only the first two lines:

```powershell
# <filename> - <A.C.R.O.N.Y.M.> — <what it does>
# Part of the Technician Toolkit - https://github.com/CursedTechnocrat/TechnicianToolkit-LiveConnect
#
# Copyright (C) 2026 CursedTechnocrat and the Technician Toolkit contributors
#
# This program is free software: you can redistribute it and/or modify
# ... (rest of the notice, unchanged)
#
# SPDX-License-Identifier: GPL-3.0-or-later
```

The notice goes **above** the `<# .SYNOPSIS #>` block. PowerShell only picks up comment-based
help when it is preceded solely by comments and blank lines, so this position keeps `Get-Help`
working while making every script self-describing when it travels alone.

## The hard rule: no interactive calls

This is what separates this repo from the main toolkit, and it is not negotiable. A single
interactive call will hang a Kaseya VSA LiveConnect terminal.

- **No `Read-Host`** — every input is a parameter
- **No `ReadKey`, no `Pause-ForKey`** — no key-wait calls of any kind
- **No `Clear-Host`** — output is never wiped mid-run
- **No ASCII banners** — the header is plain `Write-Host` lines
- **No menus, no confirmations** — behaviour is decided entirely by the parameters passed

If your tool genuinely needs a prompt or a guided menu, it belongs in the
[main toolkit](https://github.com/CursedTechnocrat/TechnicianToolkit), not here.

## The rest of the house style

- **Windows PowerShell 5.1 compatible.** That is what ships with Windows and what LiveConnect
  gives you. Do not require PowerShell 7.
- **Standalone.** No dependencies on other toolkit scripts. Each `.ps1` must work when it is
  the only file on the machine.
- **Plain status lines** — `[OK]`, `[!!]`, `[*]`, `[ERROR]` prefixes throughout.
- **Print the report or log path at the end.** The technician has to be able to retrieve it.
- **Degrade gracefully.** Hardware and modules will be missing — a desktop has no battery, a
  Server Core box may have no Defender module. Report the absence, do not throw.
- **Read-only tools stay read-only.** If a script is documented as an audit, it must not change
  system state. Anything destructive takes `-WhatIf`.
- **Keep the UTF-8 BOM.** Windows PowerShell 5.1 reads a BOM-less file as ANSI and mangles the
  output.

## Before you open a pull request

Test the script the way it will actually be used: non-interactively, with parameters only.

```powershell
# Confirm it parses
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('.\yourscript.ps1', [ref]$null, [ref]$errors)
$errors.Count   # must be 0

# Confirm no interactive calls slipped in
Select-String -Path .\yourscript.ps1 -Pattern 'Read-Host', 'ReadKey', 'Clear-Host'
```

The second check should return nothing. Then run the script end to end in a non-interactive
session and confirm it exits on its own without waiting for input.

Explain in the pull request what broke and how you hit it — the ticket that led to the fix is
usually the most useful thing you can put in the description.
