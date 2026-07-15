# Security

The toolkit is designed to be safe to run on machines you are trusted to
recover. Its guarantees:

## Downloads
- **Official sources only.** `Test-RTUrlIsOfficial` (in `Modules/Download.psm1`)
  rejects any URL that is not HTTPS or whose host is not on a hard-coded
  allow-list of vendor / project / Microsoft / GitHub / SourceForge hosts.
- **No arbitrary URLs.** The catalog in `config.json` cannot introduce a new
  download origin on its own — the host must also be added to the allow-list in
  code, which is a reviewed change.
- **Integrity.** SHA256 is verified whenever an expected hash is provided; a
  mismatch deletes the file and fails the operation. Partial downloads use a
  `.part` file and are only promoted on success.

## Privilege
- Elevation is requested only when the launcher starts, via the standard UAC
  `RunAs` prompt. Read-only actions still function without admin.
- No credentials, keys, or tokens are collected, stored, or transmitted.

## Data & privacy
- **No telemetry, analytics, ads, or bundled software.**
- Reports and logs are written only inside the toolkit folder. Nothing is sent
  anywhere.
- Registry and driver backups stay local.

## Destructive operations
Some actions modify the system (Windows Update reset, network reset, CHKDSK,
BCD rebuild, registry export/rename). They:
- Log every step via `Write-RTLog`.
- Prefer reversible approaches (e.g. renaming `SoftwareDistribution` rather than
  deleting it; creating restore points).
- Surface guidance instead of acting when an operation is unsafe from a live OS
  (e.g. Startup Repair, some `bootrec` steps are RE-only).

## Reporting a vulnerability
Open a private security advisory on the repository, or email the maintainers.
Please do not file public issues for security problems.
