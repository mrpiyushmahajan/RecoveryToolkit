# Developer Guide

## Prerequisites

- [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) — recommended.
- Windows 10/11. A VM or spare machine is ideal for testing repair operations.
- VS Code with the PowerShell extension.

## Getting started

```powershell
git clone https://github.com/YOUR_USERNAME/RecoveryToolkit.git
cd RecoveryToolkit

# Fast, non-GUI validation of config + modules + action registry:
pwsh -STA -File .\Launcher.ps1 -SelfTest -Console

# Render the GUI to a PNG without an interactive session:
pwsh -STA -File .\Launcher.ps1 -RenderScreenshot .\Docs\screenshot.png

# Run the full GUI (requests elevation):
.\Launcher.cmd
```

`-NoElevate` skips the UAC re-launch (read-only features still work);
`-Console` mirrors the log to the terminal.

## Testing a single module in isolation

Modules have a no-op `Write-RTLog` fallback, so they load standalone:

```powershell
Import-Module .\Modules\Hardware.psm1 -Force
Get-RTFullHardwareReport | ConvertTo-Json -Depth 6

Import-Module .\Modules\Download.psm1 -Force
Test-RTUrlIsOfficial 'https://aka.ms/vs/17/release/vc_redist.x64.exe'  # True
Test-RTUrlIsOfficial 'http://example.com/x.exe'                        # False
```

## Adding a portable tool or installer

Edit `config.json` — no code required:

```jsonc
{
  "id": "mytool",
  "name": "My Tool",
  "category": "Utility",
  "official": "https://vendor.example/mytool",     // provenance
  "download": "https://vendor.example/mytool.zip",  // must be an allow-listed HTTPS host
  "type": "zip",                                     // zip | exe | msi
  "exe": "MyTool.exe"                                // launched after extract
}
```

For GitHub-hosted tools use `githubRepo` + `assetPattern` instead of a static
`download`. **You must also add the host** to the allow-list in
`Test-RTUrlIsOfficial` (`Modules/Download.psm1`) — this is deliberate: new
download origins are a security decision, not a config convenience.

## Adding a feature action

Add a `New-RTAction` entry in `Launcher.ps1`:

```powershell
New-RTAction 'My Feature' 'Diagnostics' 'One-line description shown on the card.' {
    param($ctx)
    Write-RTLog 'Starting my feature...' 'Info' 'Diagnostics'
    Set-RTProgress 50
    # call any exported RT function here
    Set-RTProgress 100
}
```

Rules for action scriptblocks (they run in a fresh runspace):
- Always start with `param($ctx)`.
- Use `$ctx.Paths.*`, `$ctx.Config`, `$ctx.Root` — do **not** rely on
  launcher-scope variables.
- Use `Write-RTLog` for output and `Set-RTProgress <0-100>` for the progress bar.
- Keep them idempotent and safe to cancel (the window may close mid-run).

## Coding standards

- `Set-StrictMode -Version Latest` in every file.
- Advanced functions (`[CmdletBinding()]`) with comment-based help and
  `[OutputType]` where meaningful.
- Verb-Noun names using approved verbs; `RT` noun prefix.
- No unhandled throws in user-facing paths — return result objects
  (`Success`/`Message`) and log via `Write-RTLog`.
- No third-party PowerShell modules.
- Prefer CIM (`Get-CimInstance`) over deprecated `Get-WmiObject`.

## Linting

If you have PSScriptAnalyzer:

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery
```

## Release process

1. Bump `toolkit.version` in `config.json` and update `CHANGELOG.md`.
2. Tag and push; attach a zip of the toolkit folder to the GitHub release.
3. `Update.psm1` picks up the new tag via the releases API.
