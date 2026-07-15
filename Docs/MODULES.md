# Module Reference

Every function uses comment-based help; run `Get-Help <Function> -Full` after
importing a module. All functions are prefixed `RT` to avoid collisions.

## Download.psm1
Official-source download manager.

| Function | Purpose |
|----------|---------|
| `Test-RTUrlIsOfficial` | Validate HTTPS + host allow-list. Returns `[bool]`. |
| `Resolve-RTGitHubAsset` | Resolve latest release asset URL for `owner/repo` + pattern. |
| `Get-RTFileHash256` | SHA256 of a file. |
| `Invoke-RTDownload` | Download with resume (`.part`), retry/back-off, SHA256 verify, bandwidth limit, progress callback. |
| `Invoke-RTParallelDownload` | Concurrent downloads (PS7); sequential fallback on 5.1. |

## Update.psm1
Self-update from GitHub releases.

| Function | Purpose |
|----------|---------|
| `Compare-RTVersion` | Semantic-ish version comparison. |
| `Test-RTUpdateAvailable` | Query releases API; report latest vs current. |
| `Invoke-RTSelfUpdate` | Download + apply update, preserving data folders, backing up replaced files. |

## Hardware.psm1
CIM/WMI detection.

| Function | Purpose |
|----------|---------|
| `Get-RTProcessorInfo` / `Get-RTMemoryInfo` / `Get-RTGraphicsInfo` | CPU / RAM sticks / GPUs. |
| `Get-RTFirmwareInfo` | BIOS/UEFI, motherboard, Secure Boot, TPM. |
| `Get-RTDiskInfo` | Physical disks with type/bus + SMART reliability counters. |
| `Get-RTBatteryInfo` | Charge, design vs full-charge capacity, wear %. |
| `Get-RTNetworkInfo` / `Get-RTOSInfo` | Adapters (Wi-Fi/Ethernet/BT) / OS + machine. |
| `Get-RTFullHardwareReport` | Aggregate of everything above. |

## Repair.psm1
System repair automation.

| Function | Purpose |
|----------|---------|
| `Invoke-RTProcess` | Safe external-process wrapper (exit code + output, no throw). |
| `Invoke-RTDismRestoreHealth` / `Invoke-RTDismCheckHealth` | Component store repair/scan. |
| `Invoke-RTSfcScan` | `sfc /scannow`. |
| `Invoke-RTChkdskSchedule` | Schedule CHKDSK on reboot. |
| `Reset-RTNetworkStack` | Winsock + TCP/IP reset, DNS flush, IP release/renew. |
| `Reset-RTWindowsUpdate` | Reset update services, clear SoftwareDistribution/catroot2. |
| `Reset-RTWindowsDefender` | Reset + update signatures. |
| `Repair-RTWmi` | Verify/salvage WMI repository. |
| `Repair-RTShell` | Restart Explorer, re-register Start/Taskbar packages. |
| `Reset-RTMicrosoftStore` | `wsreset`. |

## BootRepair.psm1

| Function | Purpose |
|----------|---------|
| `Test-RTWinRE` | Detect Windows RE/WinPE. |
| `Get-RTBcdStore` | `bcdedit /enum`. |
| `Invoke-RTBootrec` | FixMbr / FixBoot / ScanOs / RebuildBcd. |
| `Repair-RTBcd` | Full bootrec sequence. |
| `Repair-RTEfiBootloader` | Rebuild EFI files via `bcdboot`. |
| `Invoke-RTStartupRepairGuidance` | Guidance text for built-in Startup Repair. |

## Drivers.psm1

| Function | Purpose |
|----------|---------|
| `Backup-RTDrivers` | DISM export of third-party drivers (timestamped folder). |
| `Restore-RTDrivers` | `pnputil` install of all `.inf` under a folder. |
| `Get-RTInstalledDrivers` / `Get-RTMissingDrivers` | Inventory / problem devices. |
| `Get-RTDriverVendorPage` | Map OEM → official driver page. |

## Diagnostics.psm1

| Function | Purpose |
|----------|---------|
| `Clear-RTTempFiles` | Delete temp; return MB freed. |
| `Invoke-RTDiskCleanup` | Launch/auto-run cleanmgr. |
| `New-RTRestorePoint` | System Restore checkpoint. |
| `Backup-RTRegistry` | Export HKLM/HKCU/HKCR. |
| `Get-RTActivationStatus` | Windows licensing status. |
| `Start-RTDefenderScan` | Quick/Full Defender scan. |
| `Get-RTRecentErrors` | Critical/error events (windowed). |
| `Get-RTStartupPrograms` | Startup entries. |

## Reports.psm1

| Function | Purpose |
|----------|---------|
| `ConvertTo-RTHtmlSection` | Object/array → HTML table section. |
| `New-RTHtmlReport` | Dark-themed HTML report from ordered sections. |
| `New-RTJsonReport` / `New-RTCsvReport` | JSON / CSV output. |
| `Get-RTInstalledSoftware` | Installed apps from uninstall registry keys. |

## PortableApps.psm1

| Function | Purpose |
|----------|---------|
| `Resolve-RTAppUrl` | Expand GitHub-release entries to a concrete URL. |
| `Get-RTPortableApp` | Download + extract (zip) or stage (exe/msi) one tool. |
| `Get-RTAllPortableApps` | Download the whole catalog. |
| `Find-RTPortableExe` / `Start-RTPortableApp` | Locate / launch a tool. |
| `Install-RTApplication` | Download + silent-install a catalog installer. |

## UI.psm1

| Function | Purpose |
|----------|---------|
| `New-RTFlatButton` | Themed flat button factory. |
| `Show-RTMainWindow` | Build and show the main window; `-RenderPngPath` for off-screen capture. |
