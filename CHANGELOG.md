# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
semantic versioning.

## [1.0.4] - 2026-07-15

### Fixed
- VLC download: the `vlc-latest-win64.exe` symlink returns HTTP 500 server-side;
  pinned to the current versioned installer URL instead.

## [1.0.3] - 2026-07-15

### Added
- **One-click bulk download** — new "All-in-One" category with three cards:
  "Download ALL Portable Tools", "Download ALL Installers (offline)", and
  "Get EVERYTHING (tools + installers)". No more downloading tools one by one.
- `-DownloadOnly` switch on `Install-RTApplication` to cache installers to the
  USB without running them (used by the bulk installer card).

## [1.0.2] - 2026-07-15

### Fixed
- **Unhandled exception "Cannot convert null to type System.Drawing.Color" when
  hovering or clicking action cards.** The hover/click handlers referenced
  `$script:RTTheme` / `$script:RTRunAction` inside `GetNewClosure()`, which
  rebinds `$script:` to a fresh module where those are null. The needed values
  are now captured as locals before the closure is created.

## [1.0.1] - 2026-07-15

### Fixed
- **Downloads failing on Windows PowerShell 5.1.** The download module now forces
  TLS 1.1/1.2/1.3 at import. 5.1 defaults to SSL3/TLS1.0, which official HTTPS
  hosts reject — this caused most downloads and all GitHub API calls to fail.
- Corrected stale/invalid catalog URLs: TestDisk now points to the 7.1 stable
  zip; Adobe Acrobat placeholder URL removed.
- Added an `openPage` fallback for tools with no stable direct link (GPU-Z,
  HWiNFO, FastCopy, Adobe Acrobat): the action opens the official download page
  instead of erroring.

## [1.0.0] - 2026-07-15

### Added
- Initial release of the Windows Recovery Toolkit.
- Modular PowerShell architecture with a thin `Launcher.ps1` orchestrator and
  ten feature modules.
- Dark-mode Windows Forms GUI (`UI.psm1`): searchable, category-filtered action
  grid, toolbar, live log, status bar and progress bar. Actions run on
  background runspaces so the UI stays responsive.
- **Download manager** (`Download.psm1`): official-source allow-list, HTTPS
  enforcement, resume, retry/back-off, SHA256 verification, bandwidth limiting,
  GitHub release resolution, and parallel downloads (PS7) with a 5.1 fallback.
- **Hardware detection** (`Hardware.psm1`): CPU, RAM, GPU, motherboard,
  BIOS/UEFI, TPM, Secure Boot, disks (NVMe/SATA + SMART), battery wear, network.
- **Repair** (`Repair.psm1`): DISM, SFC, CHKDSK scheduling, network stack reset,
  Windows Update reset, Defender reset, WMI repair, shell/Explorer repair, Store
  reset.
- **Boot repair** (`BootRepair.psm1`): bootrec sequence, EFI rebuild, WinRE
  detection, Startup Repair guidance.
- **Drivers** (`Drivers.psm1`): backup, restore, inventory, missing-driver
  detection, OEM page shortcuts.
- **Diagnostics** (`Diagnostics.psm1`): temp/disk cleanup, restore points,
  registry backup, Defender scans, event-log extraction, startup inventory.
- **Reports** (`Reports.psm1`): dark-themed HTML, JSON and CSV; installed
  software inventory.
- **Portable apps & installers** (`PortableApps.psm1`) driven by a `config.json`
  catalog of 17 portable tools and 11 silent installers, all official.
- **Self-update** (`Update.psm1`) via GitHub releases, preserving data folders.
- Global timestamped logging; portable-safe path resolution.
- `-SelfTest` and `-RenderScreenshot` launcher switches for automated validation.
- Documentation: README, Architecture, Developer Guide, Module Reference,
  Security, Contributing; MIT license.

[1.0.0]: https://github.com/mrpiyushmahajan/RecoveryToolkit/releases/tag/v1.0.0
