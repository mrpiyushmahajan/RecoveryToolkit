# Contributing

Thanks for helping improve the Windows Recovery Toolkit!

## Ground rules
- Be respectful; assume good intent.
- Keep the toolkit **safe** and **official-sources-only** — never add an
  unofficial or non-HTTPS download.
- No third-party PowerShell modules.

## Workflow
1. Fork and branch from `main` (`feature/...` or `fix/...`).
2. Make your change following the standards in
   [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md).
3. Validate:
   ```powershell
   pwsh -STA -File .\Launcher.ps1 -SelfTest -Console
   Invoke-ScriptAnalyzer -Path . -Recurse   # if available
   ```
4. Update `CHANGELOG.md` and any affected docs (`MODULES.md`, `README.md`).
5. Open a PR describing the change and how you tested it (ideally on a VM).

## What we look for
- Comment-based help on new functions and a matching row in `MODULES.md`.
- Graceful error handling — return result objects, log via `Write-RTLog`, don't
  throw into the UI.
- New download hosts added to **both** `config.json` and the allow-list in
  `Test-RTUrlIsOfficial`, with the `official` provenance URL filled in.
- PS7 features guarded so the toolkit still runs under Windows PowerShell 5.1.

## Commit style
Short imperative subject (e.g. `Add Intel SSD Toolbox to catalog`), details in
the body. Reference issues with `#123`.

## Testing repair features
Repair, boot and driver operations change real system state. Test them on a
virtual machine or a disposable install, never for the first time on a machine
you cannot afford to reimage.
