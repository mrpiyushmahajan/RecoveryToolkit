# Architecture

## Overview

The Windows Recovery Toolkit is a **modular PowerShell application** with a thin
orchestrator (`Launcher.ps1`), a set of self-contained feature modules under
`Modules/`, and a data-driven catalog (`config.json`). The GUI is Windows Forms.

```
                     ┌──────────────┐
   Launcher.cmd ───▶ │ Launcher.ps1 │  bootstraps: logging, config, elevation
                     └──────┬───────┘
                            │ imports enabled modules, builds Action registry
                            ▼
          ┌───────────────────────────────────────┐
          │              UI.psm1                    │  dark-mode WinForms shell
          │  search · sidebar · cards · log · bars  │
          └───────────────┬─────────────────────────┘
                          │ click → background runspace
        ┌─────────────────┼──────────────────────────────┐
        ▼                 ▼                                ▼
  Hardware.psm1      Repair.psm1  BootRepair.psm1   Download.psm1
  Drivers.psm1       Diagnostics.psm1               PortableApps.psm1
  Reports.psm1       Update.psm1
```

## Layers

1. **Orchestration (`Launcher.ps1`)**
   - Resolves the toolkit root in a portable-safe way (`$MyInvocation`).
   - Loads `config.json`, ensures data folders exist.
   - Defines the single global `Write-RTLog` sink (daily, timestamped file).
   - Requests UAC elevation (re-launches itself with `RunAs`).
   - Imports only the modules enabled in `config.modules`.
   - Builds the **Action registry** — a flat list of `{Name, Category,
     Description, Script}` objects. Static actions are literal scriptblocks;
     portable-tool and installer actions are generated from the catalog.
   - Hands a `Context` hashtable to the UI.

2. **Presentation (`UI.psm1`)**
   - Builds the form: toolbar (title, search, update buttons), left category
     sidebar, center `FlowLayoutPanel` of action cards, bottom log + status +
     progress.
   - Filtering is client-side over the action list (category + search text).
   - **Concurrency:** each action runs in a dedicated STA runspace so the UI
     never blocks. A `System.Threading`-safe `LogQueue` and shared `sync`
     hashtable carry log lines, status and progress back; a `Timer` (150 ms)
     drains them onto the UI thread.

3. **Domain modules (`Modules/*.psm1`)**
   - Each module is independent, exports advanced functions with comment-based
     help, and relies only on the global `Write-RTLog` (with a local no-op
     fallback so modules are testable in isolation).
   - Modules never touch the UI directly.

4. **Configuration & data (`config.json`, data folders)**
   - `settings`, `modules`, and the `portableApps` / `installers` / `vendorTools`
     catalogs are pure data. Adding a tool is a config edit, not a code change.

## Execution model for an action

```
User clicks card
      │
      ▼
UI: is another action running?  ──yes──▶ message box, abort
      │ no
      ▼
Create STA runspace ▸ set $sync + $Context ▸ BeginInvoke wrapper:
      define global:Write-RTLog → enqueue to $sync.LogQueue (+ file)
      import all modules
      run action.Script($Context)
      finally: Progress=100, Running=$false
      │
      ▼
UI Timer drains LogQueue → log box; updates status + progress bar
```

Because the action scriptblock is serialized to text and rebuilt inside the
runspace, it must be self-contained (take `$ctx`, call exported functions). It
does **not** capture launcher-scope variables.

## Portability & self-update

- All paths resolve relative to the toolkit root, so the folder runs from any
  USB drive with no registry or install footprint.
- `Update.psm1` compares the local version to the latest GitHub release and, on
  apply, overwrites only code/config — the data folders (`Downloads`, `Drivers`,
  `Logs`, `Reports`, `Cache`, `Portable`, `Installers`) are preserved and the
  replaced files are backed up under `Cache/`.

## Compatibility

Targets **PowerShell 7** (recommended) but degrades to **Windows PowerShell
5.1**: parallel downloads fall back to sequential, and GUI assemblies are loaded
explicitly at module import. `Launcher.cmd` prefers `pwsh` and falls back to
`powershell`.
