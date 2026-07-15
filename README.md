# Windows Recovery Toolkit

A portable, open-source Windows recovery and diagnostics toolkit that runs
entirely from a USB drive — no installation required. Built with **PowerShell 7**
and a modern **dark-mode Windows Forms GUI**, it downloads utilities from
**official sources only**, verifies them, and works offline once cached.

> ⚠️ **Run as Administrator.** Most repair operations need elevation. The
> launcher requests it automatically.

---

## Features

| Area | Capabilities |
|------|--------------|
| **Hardware** | CPU, GPU, RAM, motherboard, BIOS/UEFI, TPM, Secure Boot, NVMe/SATA disks, SMART health, battery wear |
| **Repair** | DISM RestoreHealth, SFC, CHKDSK scheduling, Windows Update reset, Defender reset, WMI repair, Explorer/Start/Taskbar repair, Microsoft Store reset |
| **Boot** | BCD rebuild (bootrec), EFI bootloader repair (bcdboot), Startup Repair guidance |
| **Network** | Winsock reset, TCP/IP reset, DNS flush, IP release/renew |
| **Drivers** | Backup (DISM export), restore (pnputil), inventory, missing-driver detection, OEM page shortcuts |
| **Cleanup** | Temp cleanup, Disk Cleanup, restore points, registry backup |
| **Security** | Defender quick/full scan, Microsoft Safety Scanner (catalog) |
| **Portable tools** | CrystalDiskInfo/Mark, CPU-Z, GPU-Z, HWiNFO, Everything, TestDisk/PhotoRec, Rufus, Ventoy, Sysinternals, 7-Zip, WizTree, and more |
| **Installers** | VC++ / .NET / DirectX runtimes, Chrome, Firefox, Brave, VLC, Malwarebytes, AnyDesk, TeamViewer (silent, official) |
| **Reports** | HTML, JSON and CSV — hardware, drivers, software, SMART, activation, startup |
| **Self-update** | Checks GitHub releases, updates code while preserving your data folders |

---

## Requirements

- Windows 10 or 11 (x64)
- [PowerShell 7+](https://aka.ms/powershell) (`pwsh`) — recommended
  - Falls back to Windows PowerShell 5.1 with reduced compatibility
- Administrator rights for repair features
- Internet connection for the first download of each tool (offline afterward)

---

## Quick start

1. Copy the `RecoveryToolkit` folder to your USB drive.
2. Double-click **`Launcher.cmd`** (or run `pwsh -STA -File Launcher.ps1`).
3. Approve the UAC elevation prompt.
4. Use the search box and category sidebar to find an action; click a card to run it.

Everything a tool downloads is stored under the toolkit folder, so the USB drive
stays fully portable.

---

## Project layout

```
RecoveryToolkit/
├── Launcher.ps1        # Orchestrator: logging, config, modules, action registry, GUI
├── Launcher.cmd        # Double-click entry point (prefers pwsh)
├── config.json         # Settings + official download catalog
├── Modules/
│   ├── Download.psm1     # Official-source download manager (resume, retry, SHA256, parallel)
│   ├── Update.psm1       # GitHub self-update
│   ├── Hardware.psm1     # CIM/WMI hardware detection
│   ├── Drivers.psm1      # Driver backup/restore/inventory
│   ├── Repair.psm1       # DISM/SFC/network/update/WMI/shell repairs
│   ├── BootRepair.psm1   # BCD/EFI/startup repair
│   ├── Diagnostics.psm1  # Cleanup, restore points, registry, Defender, events
│   ├── Reports.psm1      # HTML/JSON/CSV reporting
│   ├── PortableApps.psm1 # Portable tool + installer management
│   └── UI.psm1           # Dark-mode WinForms GUI
├── Portable/  Installers/  Downloads/  Drivers/  Logs/  Reports/  Cache/
└── Docs/       # Developer guide, architecture, module reference, contributing
```

See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) and
[Docs/DEVELOPER_GUIDE.md](Docs/DEVELOPER_GUIDE.md) for internals.

---

## Configuration

`config.json` controls behavior and the download catalog:

```jsonc
"settings": {
  "portableMode": true,        // keep all data inside the toolkit folder
  "offlineMode": false,        // use only already-downloaded tools
  "maxParallelDownloads": 3,
  "downloadRetries": 3,
  "bandwidthLimitKBps": 0,     // 0 = unlimited
  "verifyHashes": true,
  "requireHttps": true
},
"modules": { "Download": true, "Hardware": true, ... }  // enable/disable modules
```

Add or update tools by editing the `portableApps` / `installers` arrays. Every
entry keeps an `official` URL for provenance; downloads are restricted to an
HTTPS host allow-list enforced in `Download.psm1`.

---

## Security model

- **Official sources only.** `Test-RTUrlIsOfficial` rejects any non-HTTPS URL or
  host that is not on the vetted allow-list.
- **Verification.** SHA256 is checked whenever an expected hash is supplied.
- **No telemetry, no ads, no bundled software.**
- **Least privilege.** Elevation is requested only when needed; the toolkit runs
  read-only actions without admin where possible.

See [Docs/SECURITY.md](Docs/SECURITY.md).

---

## Contributing

Contributions are welcome — see [Docs/CONTRIBUTING.md](Docs/CONTRIBUTING.md) and
the [CHANGELOG](CHANGELOG.md). Please keep to the coding standards (advanced
functions, comment-based help, strict mode, graceful error handling).

## License

[MIT](LICENSE) — provided "as is", without warranty. You are responsible for how
you use recovery and repair operations on your systems.
