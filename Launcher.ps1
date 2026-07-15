#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point for the Windows Recovery Toolkit.
.DESCRIPTION
    Bootstraps logging, loads configuration, imports all enabled modules, builds
    the action registry that maps toolkit features to module functions, and
    launches the Windows Forms GUI. Requests elevation when required.
.NOTES
    Run via Launcher.cmd (recommended) or: pwsh -STA -File Launcher.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoElevate,
    [switch]$Console,
    [switch]$SelfTest,          # Build config/modules/actions and exit without showing the GUI.
    [string]$RenderScreenshot,  # Render the GUI off-screen to this PNG path, then exit.
    [string]$RenderCategory,    # Category to pre-select in the rendered screenshot.
    [string]$RenderLogFile      # Log file whose lines are preloaded into the rendered log pane.
)

if ($SelfTest -or $RenderScreenshot) { $NoElevate = $true }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Resolve toolkit root (portable-safe) ----------------------------------
$script:RTRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $script:RTRoot

# --- Load configuration ----------------------------------------------------
$configPath = Join-Path $script:RTRoot 'config.json'
if (-not (Test-Path $configPath)) { throw "config.json not found at $configPath" }
$script:RTConfig = Get-Content $configPath -Raw | ConvertFrom-Json

# --- Resolve data paths ----------------------------------------------------
function Resolve-RTPath { param([string]$Sub) $p = Join-Path $script:RTRoot $Sub; if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }; return $p }
$paths = @{
    Portable   = Resolve-RTPath $script:RTConfig.paths.portable
    Installers = Resolve-RTPath $script:RTConfig.paths.installers
    Downloads  = Resolve-RTPath $script:RTConfig.paths.downloads
    Drivers    = Resolve-RTPath $script:RTConfig.paths.drivers
    Logs       = Resolve-RTPath $script:RTConfig.paths.logs
    Reports    = Resolve-RTPath $script:RTConfig.paths.reports
    Cache      = Resolve-RTPath $script:RTConfig.paths.cache
}

# --- Global logging --------------------------------------------------------
$script:RTLogFile = Join-Path $paths.Logs ("toolkit_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
function global:Write-RTLog {
    <#
    .SYNOPSIS
        Writes a timestamped, leveled, categorized entry to the daily log file.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Debug','Info','Warning','Error')][string]$Level = 'Info',
        [string]$Category = 'General'
    )
    $line = "{0} [{1,-7}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Category, $Message
    try { Add-Content -Path $script:RTLogFile -Value $line -ErrorAction Stop } catch {}
    if ($Console) {
        $color = switch ($Level) { 'Error' {'Red'} 'Warning' {'Yellow'} 'Debug' {'DarkGray'} default {'Gray'} }
        Write-Host $line -ForegroundColor $color
    }
}

# --- Elevation -------------------------------------------------------------
function Test-RTAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return ([System.Security.Principal.WindowsPrincipal]$id).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-RTAdmin) -and -not $NoElevate) {
    Write-RTLog -Message 'Elevation required; relaunching as administrator.' -Level 'Info' -Category 'Launcher'
    try {
        $pwsh = (Get-Process -Id $PID).Path
        Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList @('-STA','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
        return
    } catch {
        Write-RTLog -Message "Could not elevate: $($_.Exception.Message). Continuing without admin (some features limited)." -Level 'Warning' -Category 'Launcher'
    }
}

Write-RTLog -Message "=== $($script:RTConfig.toolkit.name) v$($script:RTConfig.toolkit.version) starting (Admin=$(Test-RTAdmin)) ===" -Level 'Info' -Category 'Launcher'

# --- Import enabled modules ------------------------------------------------
$moduleDir = Join-Path $script:RTRoot 'Modules'
foreach ($mod in $script:RTConfig.modules.PSObject.Properties) {
    if (-not $mod.Value) { continue }
    $mPath = Join-Path $moduleDir "$($mod.Name).psm1"
    if (Test-Path $mPath) {
        try { Import-Module $mPath -Force -DisableNameChecking; Write-RTLog -Message "Loaded module $($mod.Name)" -Level 'Debug' -Category 'Launcher' }
        catch { Write-RTLog -Message "Failed to load $($mod.Name): $($_.Exception.Message)" -Level 'Error' -Category 'Launcher' }
    }
}

# ---------------------------------------------------------------------------
#  Action registry
#  Each action's Script runs in a fresh background runspace. The UI runner
#  imports every module and defines the Write-RTLog / Log / Set-RTProgress
#  helpers before invoking the action, so actions call RT functions directly.
# ---------------------------------------------------------------------------
function New-RTAction {
    param([string]$Name, [string]$Category, [string]$Description, [scriptblock]$Script)
    [pscustomobject]@{ Name = $Name; Category = $Category; Description = $Description; Script = $Script }
}

$actions = @(
    # --- One-click bulk ---
    New-RTAction 'Download ALL Portable Tools' 'All-in-One' 'One click: download and extract every portable tool in the catalog to the USB.' {
        param($ctx)
        $apps = @($ctx.Config.portableApps); $n = $apps.Count; $i = 0; $ok = 0; $manual = 0
        Write-RTLog "Downloading all $n portable tools..." 'Info' 'PortableApps'
        foreach ($app in $apps) {
            $i++; Set-RTProgress ([int]((($i - 1) / $n) * 100))
            Write-RTLog "[$i/$n] $($app.name)" 'Info' 'PortableApps'
            $r = Get-RTPortableApp -App $app -PortableRoot $ctx.Paths.Portable -DownloadRoot $ctx.Paths.Downloads
            if ($r.OpenedPage) { $manual++ } elseif ($r.Success) { $ok++ } else { Write-RTLog "   failed: $($r.Message)" 'Warning' 'PortableApps' }
        }
        Set-RTProgress 100
        Write-RTLog "Portable tools: $ok downloaded, $manual opened for manual download, $($n-$ok-$manual) failed." 'Info' 'PortableApps'
    }
    New-RTAction 'Download ALL Installers (offline)' 'All-in-One' 'One click: cache every installer (browsers, runtimes, etc.) to the USB without running them.' {
        param($ctx)
        $insts = @($ctx.Config.installers); $n = $insts.Count; $i = 0; $ok = 0; $skip = 0
        Write-RTLog "Caching all $n installers to the USB..." 'Info' 'PortableApps'
        foreach ($inst in $insts) {
            $i++; Set-RTProgress ([int]((($i - 1) / $n) * 100))
            Write-RTLog "[$i/$n] $($inst.name)" 'Info' 'PortableApps'
            $r = Install-RTApplication -Installer $inst -InstallerRoot $ctx.Paths.Installers -DownloadOnly
            if ($r.Skipped) { $skip++ } elseif ($r.Success) { $ok++ } else { Write-RTLog "   failed: $($r.Message)" 'Warning' 'PortableApps' }
        }
        Set-RTProgress 100
        Write-RTLog "Installers: $ok cached, $skip need manual download, $($n-$ok-$skip) failed. Files are in the Installers folder." 'Info' 'PortableApps'
    }
    New-RTAction 'Get EVERYTHING (tools + installers)' 'All-in-One' 'One click: download all portable tools AND cache all installers to the USB.' {
        param($ctx)
        $apps = @($ctx.Config.portableApps); $insts = @($ctx.Config.installers)
        $total = $apps.Count + $insts.Count; $done = 0; $ok = 0
        Write-RTLog "Getting everything: $($apps.Count) tools + $($insts.Count) installers..." 'Info' 'PortableApps'
        foreach ($app in $apps) {
            $done++; Set-RTProgress ([int]((($done - 1) / $total) * 100))
            Write-RTLog "[$done/$total] tool: $($app.name)" 'Info' 'PortableApps'
            $r = Get-RTPortableApp -App $app -PortableRoot $ctx.Paths.Portable -DownloadRoot $ctx.Paths.Downloads
            if ($r.Success) { $ok++ }
        }
        foreach ($inst in $insts) {
            $done++; Set-RTProgress ([int]((($done - 1) / $total) * 100))
            Write-RTLog "[$done/$total] installer: $($inst.name)" 'Info' 'PortableApps'
            $r = Install-RTApplication -Installer $inst -InstallerRoot $ctx.Paths.Installers -DownloadOnly
            if ($r.Success) { $ok++ }
        }
        Set-RTProgress 100
        Write-RTLog "All done: $ok/$total succeeded. Anything not downloaded had no direct link (open its official page manually)." 'Info' 'PortableApps'
    }

    # --- Hardware & Reports ---
    New-RTAction 'Hardware Information' 'Hardware' 'Detect CPU, GPU, RAM, board, BIOS, TPM, Secure Boot.' {
        param($ctx)
        $hw = Get-RTFullHardwareReport
        Write-RTLog "CPU: $($hw.CPU.Name)" 'Info' 'Hardware'
        Write-RTLog "RAM: $($hw.Memory.TotalGB) GB | GPU: $(($hw.GPU | ForEach-Object Name) -join ', ')" 'Info' 'Hardware'
        Write-RTLog "Firmware: $($hw.Firmware.FirmwareType) | SecureBoot: $($hw.Firmware.SecureBoot) | TPM present: $($hw.Firmware.TPM.Present)" 'Info' 'Hardware'
    }
    New-RTAction 'SSD Health' 'Hardware' 'Report disk type, health and wear per physical drive.' {
        param($ctx)
        foreach ($d in Get-RTDiskInfo) { Write-RTLog "$($d.FriendlyName) [$($d.MediaType)/$($d.BusType)] $($d.SizeGB)GB Health=$($d.HealthStatus) Wear=$($d.Wear) Temp=$($d.TemperatureC)C" 'Info' 'Hardware' }
    }
    New-RTAction 'SMART Report' 'Hardware' 'Export SMART/reliability counters for all disks.' {
        param($ctx)
        $out = Join-Path $ctx.Paths.Reports ("SMART_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-RTCsvReport -Data (Get-RTDiskInfo) -Path $out; Write-RTLog "SMART report: $out" 'Info' 'Reports'
    }
    New-RTAction 'Battery Health' 'Hardware' 'Show battery charge, capacity and estimated wear.' {
        param($ctx)
        $b = Get-RTBatteryInfo
        if ($b.Present) { Write-RTLog "Battery $($b.ChargePercent)% | Wear: $($b.WearPercent)% | Design: $($b.DesignCapacitymWh) Full: $($b.FullChargeCapmWh)" 'Info' 'Hardware' }
        else { Write-RTLog 'No battery detected (desktop).' 'Info' 'Hardware' }
    }
    New-RTAction 'System Report' 'Reports' 'Generate full HTML + JSON system report.' {
        param($ctx)
        $hw = Get-RTFullHardwareReport
        $sections = [ordered]@{
            'Operating System' = $hw.OS; 'Processor' = $hw.CPU; 'Memory' = $hw.Memory.Modules
            'Graphics' = $hw.GPU; 'Firmware & Security' = $hw.Firmware; 'Disks' = $hw.Disks
            'Battery' = $hw.Battery; 'Network' = $hw.Network
            'Activation' = (Get-RTActivationStatus); 'Startup Programs' = (Get-RTStartupPrograms)
        }
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $html = New-RTHtmlReport -Sections $sections -Path (Join-Path $ctx.Paths.Reports "SystemReport_$stamp.html")
        New-RTJsonReport -Data $hw -Path (Join-Path $ctx.Paths.Reports "SystemReport_$stamp.json") | Out-Null
        Write-RTLog "Report: $html" 'Info' 'Reports'; Start-Process $html
    }
    New-RTAction 'Export Driver Report' 'Reports' 'List installed drivers to CSV.' {
        param($ctx)
        $out = Join-Path $ctx.Paths.Reports ("Drivers_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-RTCsvReport -Data (Get-RTInstalledDrivers) -Path $out; Write-RTLog "Driver report: $out" 'Info' 'Reports'
    }
    New-RTAction 'Export Installed Software' 'Reports' 'List installed applications to CSV.' {
        param($ctx)
        $out = Join-Path $ctx.Paths.Reports ("Software_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        New-RTCsvReport -Data (Get-RTInstalledSoftware) -Path $out; Write-RTLog "Software report: $out" 'Info' 'Reports'
    }
    New-RTAction 'Windows Activation' 'Reports' 'Show Windows licensing/activation status.' {
        param($ctx)
        $a = Get-RTActivationStatus; Write-RTLog "$($a.Name) => $($a.Status) (key ...$($a.PartialKey))" 'Info' 'Diagnostics'
    }

    # --- Repair ---
    New-RTAction 'Windows Repair (DISM+SFC)' 'Repair' 'Run DISM RestoreHealth then SFC scannow.' {
        param($ctx)
        Set-RTProgress 10; Write-RTLog 'DISM RestoreHealth...' 'Info' 'Repair'
        $d = Invoke-RTDismRestoreHealth; Write-RTLog "DISM exit $($d.ExitCode)" 'Info' 'Repair'
        Set-RTProgress 60; Write-RTLog 'SFC scannow...' 'Info' 'Repair'
        $s = Invoke-RTSfcScan; Write-RTLog "SFC exit $($s.ExitCode)" 'Info' 'Repair'; Set-RTProgress 100
    }
    New-RTAction 'Windows Update Repair' 'Repair' 'Reset update services and clear SoftwareDistribution.' {
        param($ctx)
        $r = Reset-RTWindowsUpdate; foreach ($k in $r.Keys) { Write-RTLog "$k => $($r[$k])" 'Info' 'Repair' }
    }
    New-RTAction 'Network Repair' 'Repair' 'Reset Winsock/TCP-IP, flush DNS, renew IP.' {
        param($ctx)
        $r = Reset-RTNetworkStack; foreach ($k in $r.Keys) { Write-RTLog "$k exit $($r[$k].ExitCode)" 'Info' 'Repair' }
    }
    New-RTAction 'Reset Defender' 'Repair' 'Reset and update Microsoft Defender signatures.' {
        param($ctx)
        $r = Reset-RTWindowsDefender; foreach ($k in $r.Keys) { Write-RTLog "$k done" 'Info' 'Repair' }
    }
    New-RTAction 'Repair WMI' 'Repair' 'Verify and salvage the WMI repository.' {
        param($ctx)
        $r = Repair-RTWmi; foreach ($k in $r.Keys) { Write-RTLog "$k => $($r[$k].Output)" 'Info' 'Repair' }
    }
    New-RTAction 'Repair Explorer / Start / Taskbar' 'Repair' 'Restart Explorer and re-register shell packages.' {
        param($ctx)
        $r = Repair-RTShell; foreach ($k in $r.Keys) { Write-RTLog "$k => $($r[$k])" 'Info' 'Repair' }
    }
    New-RTAction 'Repair Microsoft Store' 'Repair' 'Reset the Microsoft Store cache (wsreset).' {
        param($ctx)
        Reset-RTMicrosoftStore | Out-Null; Write-RTLog 'Microsoft Store cache reset triggered.' 'Info' 'Repair'
    }
    New-RTAction 'Schedule CHKDSK' 'Repair' 'Schedule a full CHKDSK of C: on next reboot.' {
        param($ctx)
        $r = Invoke-RTChkdskSchedule -Drive 'C'; Write-RTLog "CHKDSK scheduled (exit $($r.ExitCode))." 'Info' 'Repair'
    }

    # --- Boot ---
    New-RTAction 'BCD Repair' 'Boot' 'Run FixMbr, FixBoot, ScanOs, RebuildBcd.' {
        param($ctx)
        $r = Repair-RTBcd; foreach ($k in $r.Keys) { Write-RTLog "$k exit $($r[$k].ExitCode)" 'Info' 'BootRepair' }
    }
    New-RTAction 'Boot Repair (EFI)' 'Boot' 'Rebuild EFI boot files with bcdboot.' {
        param($ctx)
        $r = Repair-RTEfiBootloader; Write-RTLog "bcdboot exit $($r.ExitCode)" 'Info' 'BootRepair'
    }
    New-RTAction 'Startup Repair Guidance' 'Boot' 'Show how to launch Windows Startup Repair.' {
        param($ctx)
        foreach ($l in (Invoke-RTStartupRepairGuidance) -split "`n") { Write-RTLog $l.Trim() 'Info' 'BootRepair' }
    }

    # --- Drivers ---
    New-RTAction 'Driver Backup' 'Drivers' 'Export all third-party drivers via DISM.' {
        param($ctx)
        $r = Backup-RTDrivers -Destination $ctx.Paths.Drivers; Write-RTLog "Drivers exported to $($r.Path)" 'Info' 'Drivers'
    }
    New-RTAction 'Driver Restore' 'Drivers' 'Reinstall drivers from the latest backup folder.' {
        param($ctx)
        $latest = Get-ChildItem $ctx.Paths.Drivers -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $r = Restore-RTDrivers -Source $latest.FullName; Write-RTLog "Restore exit $($r.ExitCode)" 'Info' 'Drivers' }
        else { Write-RTLog 'No driver backup found. Run Driver Backup first.' 'Warning' 'Drivers' }
    }
    New-RTAction 'Detect Missing Drivers' 'Drivers' 'List devices with driver problems.' {
        param($ctx)
        $m = Get-RTMissingDrivers; if ($m) { foreach ($d in $m) { Write-RTLog "MISSING: $($d.Name) (err $($d.ErrorCode))" 'Warning' 'Drivers' } } else { Write-RTLog 'No missing drivers detected.' 'Info' 'Drivers' }
    }
    New-RTAction 'Open Driver Vendor Page' 'Drivers' 'Open the OEM driver download page for this PC.' {
        param($ctx)
        $v = Get-RTDriverVendorPage; Write-RTLog "$($v.Manufacturer): $($v.Url)" 'Info' 'Drivers'; Start-Process $v.Url
    }

    # --- Cleanup & Maintenance ---
    New-RTAction 'Temp Cleanup' 'Cleanup' 'Delete user and system temp files.' {
        param($ctx)
        $r = Clear-RTTempFiles; Write-RTLog "Freed ~$($r.FreedMB) MB ($($r.SkippedFiles) skipped)." 'Info' 'Diagnostics'
    }
    New-RTAction 'Disk Cleanup' 'Cleanup' 'Launch Windows Disk Cleanup.' {
        param($ctx)
        Invoke-RTDiskCleanup | Out-Null; Write-RTLog 'Disk Cleanup launched.' 'Info' 'Diagnostics'
    }
    New-RTAction 'Create Restore Point' 'Cleanup' 'Create a System Restore checkpoint.' {
        param($ctx)
        $r = New-RTRestorePoint; Write-RTLog $r.Output ($(if($r.Success){'Info'}else{'Warning'})) 'Diagnostics'
    }
    New-RTAction 'Registry Backup' 'Cleanup' 'Export HKLM/HKCU/HKCR registry hives.' {
        param($ctx)
        $dest = Join-Path $ctx.Paths.Reports 'RegistryBackup'; Backup-RTRegistry -Destination $dest | Out-Null; Write-RTLog "Registry exported to $dest" 'Info' 'Diagnostics'
    }
    New-RTAction 'Defender Quick Scan' 'Security' 'Run a Microsoft Defender quick scan.' {
        param($ctx)
        Write-RTLog 'Running Defender quick scan...' 'Info' 'Diagnostics'; $r = Start-RTDefenderScan -ScanType Quick; Write-RTLog "Scan exit $($r.ExitCode)" 'Info' 'Diagnostics'
    }
    New-RTAction 'Recent System Errors' 'Diagnostics' 'Show critical/error events from the last 24h.' {
        param($ctx)
        $e = Get-RTRecentErrors -Hours 24 -Max 40
        if ($e) { foreach ($x in $e) { Write-RTLog "$($x.TimeCreated) $($x.ProviderName) [$($x.Id)] $($x.Message)" 'Warning' 'Diagnostics' } } else { Write-RTLog 'No recent errors.' 'Info' 'Diagnostics' }
    }
)

# --- Portable tools & installers as actions --------------------------------
foreach ($app in $script:RTConfig.portableApps) {
    $actions += New-RTAction "Get: $($app.name)" 'Portable Tools' "Download & extract $($app.name) from its official source." ([scriptblock]::Create(@"
param(`$ctx)
`$app = (`$ctx.Config.portableApps | Where-Object { `$_.id -eq '$($app.id)' })
Write-RTLog 'Downloading $($app.name)...' 'Info' 'PortableApps'
`$r = Get-RTPortableApp -App `$app -PortableRoot `$ctx.Paths.Portable -DownloadRoot `$ctx.Paths.Downloads
if (`$r.Success) { Write-RTLog '$($app.name) ready. Launching...' 'Info' 'PortableApps'; Start-RTPortableApp -App `$app -PortableRoot `$ctx.Paths.Portable | Out-Null }
else { Write-RTLog 'Failed: ' + `$r.Message 'Error' 'PortableApps' }
"@))
}
foreach ($inst in $script:RTConfig.installers) {
    $actions += New-RTAction "Install: $($inst.name)" 'Installers' "Download & silently install $($inst.name) (official)." ([scriptblock]::Create(@"
param(`$ctx)
`$inst = (`$ctx.Config.installers | Where-Object { `$_.id -eq '$($inst.id)' })
Write-RTLog 'Installing $($inst.name)...' 'Info' 'PortableApps'
`$r = Install-RTApplication -Installer `$inst -InstallerRoot `$ctx.Paths.Installers -Silent
Write-RTLog ('$($inst.name): ' + `$r.Message) (`$(if(`$r.Success){'Info'}else{'Error'})) 'PortableApps'
"@))
}

# --- Native tool shortcuts -------------------------------------------------
$nativeTools = @(
    @{ Name='Event Viewer'; Cmd='eventvwr.msc'; Desc='Open Windows Event Viewer.' }
    @{ Name='Device Manager'; Cmd='devmgmt.msc'; Desc='Open Device Manager.' }
    @{ Name='Services'; Cmd='services.msc'; Desc='Open the Services console.' }
    @{ Name='Command Prompt (Admin)'; Cmd='cmd.exe'; Desc='Open an elevated Command Prompt.' }
    @{ Name='PowerShell (Admin)'; Cmd='pwsh.exe'; Desc='Open an elevated PowerShell 7.' }
)
foreach ($t in $nativeTools) {
    $actions += New-RTAction $t.Name 'System Tools' $t.Desc ([scriptblock]::Create(@"
param(`$ctx); Start-Process '$($t.Cmd)'; Write-RTLog 'Launched $($t.Name).' 'Info' 'System'
"@))
}

$categories = $actions | ForEach-Object Category | Sort-Object -Unique

# --- Build context & handlers ----------------------------------------------
$context = @{
    Config          = $script:RTConfig
    Root            = $script:RTRoot
    Paths           = $paths
    Actions         = $actions
    Categories      = $categories
    LogFile         = $script:RTLogFile
    OnUpdateToolkit = {
        param($sync)
        $repo = ($script:RTConfig.toolkit.repository -replace '^https?://github.com/', '')
        $sync.LogQueue.Enqueue("Checking for toolkit updates ($repo)...")
        $info = Test-RTUpdateAvailable -Repo $repo -CurrentVersion $script:RTConfig.toolkit.version
        if ($info.UpdateAvailable) { $sync.LogQueue.Enqueue("Update available: $($info.LatestVersion). Use releases page to apply.") }
        else { $sync.LogQueue.Enqueue("Up to date (v$($info.CurrentVersion)).") }
    }
    OnUpdateTools   = {
        param($sync)
        $sync.LogQueue.Enqueue('Re-downloading all portable tools in the background...')
        $r = Get-RTAllPortableApps -Catalog $script:RTConfig.portableApps -PortableRoot $paths.Portable -DownloadRoot $paths.Downloads -StatusCallback { param($m) $sync.LogQueue.Enqueue($m) }
        $ok = ($r | Where-Object Success).Count
        $sync.LogQueue.Enqueue("Tools updated: $ok/$($r.Count) succeeded.")
    }
}

# --- Launch GUI ------------------------------------------------------------
Write-RTLog -Message "Loaded $($actions.Count) actions across $($categories.Count) categories." -Level 'Info' -Category 'Launcher'
if ($SelfTest) {
    Write-Host "SELF-TEST OK: $($actions.Count) actions, $($categories.Count) categories, $($context.Config.portableApps.Count) portable + $($context.Config.installers.Count) installers." -ForegroundColor Green
    Write-Host "Categories: $($categories -join ', ')"
    Write-Host "Log file: $script:RTLogFile"
    return
}
if ($RenderScreenshot) {
    Show-RTMainWindow -Context $context -RenderPngPath $RenderScreenshot -InitialCategory $RenderCategory -PreloadLogFile $RenderLogFile
    Write-Host "Rendered GUI to $RenderScreenshot" -ForegroundColor Green
    return
}
Show-RTMainWindow -Context $context
Write-RTLog -Message '=== Toolkit closed ===' -Level 'Info' -Category 'Launcher'
