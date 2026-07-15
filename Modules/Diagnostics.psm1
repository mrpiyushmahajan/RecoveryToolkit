<#
.SYNOPSIS
    System diagnostics, cleanup and maintenance for the Recovery Toolkit.
.DESCRIPTION
    Disk/temp cleanup, restore points, registry backup, Defender quick scan,
    activation status, event-log error extraction and startup program inventory.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}
if (-not (Get-Command -Name Invoke-RTProcess -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Repair.psm1') -Force
}

function Clear-RTTempFiles {
    <#
    .SYNOPSIS
        Deletes user and system temp files, returning bytes reclaimed.
    #>
    [CmdletBinding()] param()
    $targets = @($env:TEMP, (Join-Path $env:windir 'Temp'), (Join-Path $env:LOCALAPPDATA 'Temp'))
    $freed = 0L; $errors = 0
    foreach ($t in ($targets | Select-Object -Unique)) {
        if (-not (Test-Path $t)) { continue }
        Get-ChildItem -Path $t -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { $freed += $_.Length; Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop }
            catch { $errors++ }
        }
    }
    $mb = [math]::Round($freed / 1MB, 2)
    Write-RTLog -Message "Temp cleanup freed ~$mb MB ($errors files locked/skipped)." -Level 'Info' -Category 'Diagnostics'
    return [pscustomobject]@{ FreedMB = $mb; SkippedFiles = $errors }
}

function Invoke-RTDiskCleanup {
    <#
    .SYNOPSIS
        Launches the built-in Disk Cleanup (cleanmgr) with a preset profile.
    #>
    [CmdletBinding()]
    param([switch]$AutoRun)
    if ($AutoRun) {
        return Invoke-RTProcess -FilePath 'cleanmgr.exe' -Arguments '/sagerun:65535' -SuccessCodes @(0)
    }
    Start-Process 'cleanmgr.exe' -ArgumentList '/lowdisk'
    return [pscustomobject]@{ Success = $true; Output = 'Disk Cleanup launched.' }
}

function New-RTRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore point.
    .PARAMETER Description
        Restore point label.
    #>
    [CmdletBinding()]
    param([string]$Description = "RecoveryToolkit $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-RTLog -Message "Restore point created: $Description" -Level 'Info' -Category 'Diagnostics'
        return [pscustomobject]@{ Success = $true; Output = "Created: $Description" }
    } catch {
        Write-RTLog -Message "Restore point failed: $($_.Exception.Message)" -Level 'Error' -Category 'Diagnostics'
        return [pscustomobject]@{ Success = $false; Output = $_.Exception.Message }
    }
}

function Backup-RTRegistry {
    <#
    .SYNOPSIS
        Exports the main registry hives to a destination folder.
    .PARAMETER Destination
        Folder to receive the .reg exports.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $hives = @{ HKLM = 'HKLM'; HKCU = 'HKCU'; HKCR = 'HKCR' }
    $results = [ordered]@{}
    foreach ($h in $hives.Keys) {
        $file = Join-Path $Destination "$($h)_$stamp.reg"
        $results[$h] = Invoke-RTProcess -FilePath 'reg.exe' -Arguments 'export',$hives[$h],$file,'/y'
    }
    Write-RTLog -Message "Registry exported to $Destination" -Level 'Info' -Category 'Diagnostics'
    return $results
}

function Get-RTActivationStatus {
    <#
    .SYNOPSIS
        Returns Windows activation/licensing status.
    #>
    [CmdletBinding()] param()
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop |
            Select-Object -First 1
        $status = switch ($lic.LicenseStatus) { 0 {'Unlicensed'} 1 {'Licensed'} 2 {'OOB Grace'} 3 {'OOT Grace'} 4 {'Non-Genuine Grace'} 5 {'Notification'} 6 {'Extended Grace'} default {'Unknown'} }
        return [pscustomobject]@{
            Name        = $lic.Name
            Description = $lic.Description
            Status      = $status
            PartialKey  = $lic.PartialProductKey
        }
    } catch {
        Write-RTLog -Message "Activation query failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Diagnostics'
        return [pscustomobject]@{ Status = 'Unknown'; Name = $null }
    }
}

function Start-RTDefenderScan {
    <#
    .SYNOPSIS
        Runs a Microsoft Defender scan.
    .PARAMETER ScanType
        Quick or Full.
    #>
    [CmdletBinding()]
    param([ValidateSet('Quick','Full')][string]$ScanType = 'Quick')
    $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (-not (Test-Path $mp)) { return [pscustomobject]@{ Success = $false; Output = 'Defender not available.' } }
    $type = if ($ScanType -eq 'Full') { 2 } else { 1 }
    return Invoke-RTProcess -FilePath $mp -Arguments '-Scan','-ScanType',$type -SuccessCodes @(0, 2)
}

function Get-RTRecentErrors {
    <#
    .SYNOPSIS
        Returns recent System/Application error events.
    .PARAMETER Hours
        Look-back window in hours.
    #>
    [CmdletBinding()]
    param([int]$Hours = 24, [int]$Max = 100)
    $since = (Get-Date).AddHours(-$Hours)
    try {
        return Get-WinEvent -FilterHashtable @{ LogName = 'System','Application'; Level = 1,2; StartTime = $since } -MaxEvents $Max -ErrorAction Stop |
            Select-Object TimeCreated, LogName, ProviderName, Id, LevelDisplayName, @{N='Message';E={ ($_.Message -split "`n")[0] }}
    } catch {
        Write-RTLog -Message "Event log query returned no results or failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Diagnostics'
        return @()
    }
}

function Get-RTStartupPrograms {
    <#
    .SYNOPSIS
        Returns programs configured to run at startup.
    #>
    [CmdletBinding()] param()
    try {
        return Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
            Select-Object Name, Command, Location, User
    } catch { return @() }
}

Export-ModuleMember -Function Clear-RTTempFiles, Invoke-RTDiskCleanup, New-RTRestorePoint, Backup-RTRegistry,
    Get-RTActivationStatus, Start-RTDefenderScan, Get-RTRecentErrors, Get-RTStartupPrograms
