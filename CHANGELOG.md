# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/) and this project adheres to
semantic versioning.

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
