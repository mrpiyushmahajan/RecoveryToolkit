<#
.SYNOPSIS
    Boot and BCD repair helpers for the Recovery Toolkit.
.DESCRIPTION
    Wraps bootrec, bcdedit and startup-repair guidance. These operations are most
    effective from Windows RE / WinPE; when run from a live OS they surface guidance.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}
if (-not (Get-Command -Name Invoke-RTProcess -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Repair.psm1') -Force
}

function Test-RTWinRE {
    <#
    .SYNOPSIS
        Returns $true when running inside Windows RE / WinPE.
    #>
    [CmdletBinding()] param()
    return (Test-Path 'X:\Windows\System32') -or ($env:SystemDrive -eq 'X:')
}

function Get-RTBcdStore {
    <#
    .SYNOPSIS
        Dumps the current BCD store via bcdedit /enum.
    #>
    [CmdletBinding()] param()
    return Invoke-RTProcess -FilePath 'bcdedit.exe' -Arguments '/enum'
}

function Invoke-RTBootrec {
    <#
    .SYNOPSIS
        Runs a bootrec operation (FixMbr, FixBoot, ScanOs, RebuildBcd).
    .PARAMETER Operation
        One of FixMbr, FixBoot, ScanOs, RebuildBcd.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('FixMbr','FixBoot','ScanOs','RebuildBcd')][string]$Operation
    )
    if (-not (Test-RTWinRE)) {
        Write-RTLog -Message "bootrec /$Operation is intended for Windows RE. Running from live OS may fail or be limited." -Level 'Warning' -Category 'BootRepair'
    }
    return Invoke-RTProcess -FilePath 'bootrec.exe' -Arguments "/$Operation" -SuccessCodes @(0)
}

function Repair-RTBcd {
    <#
    .SYNOPSIS
        Runs the standard BCD rebuild sequence: FixMbr, FixBoot, ScanOs, RebuildBcd.
    #>
    [CmdletBinding()] param()
    $result = [ordered]@{}
    foreach ($op in 'FixMbr','FixBoot','ScanOs','RebuildBcd') {
        $result[$op] = Invoke-RTBootrec -Operation $op
    }
    return $result
}

function Repair-RTEfiBootloader {
    <#
    .SYNOPSIS
        Rebuilds the EFI boot files using bcdboot for the Windows installation.
    .PARAMETER WindowsPath
        Path to the Windows directory (default $env:windir).
    #>
    [CmdletBinding()]
    param([string]$WindowsPath = $env:windir)
    Write-RTLog -Message "Rebuilding EFI bootloader from $WindowsPath" -Level 'Info' -Category 'BootRepair'
    return Invoke-RTProcess -FilePath 'bcdboot.exe' -Arguments $WindowsPath,'/f','ALL' -SuccessCodes @(0)
}

function Invoke-RTStartupRepairGuidance {
    <#
    .SYNOPSIS
        Returns actionable guidance for launching the built-in Startup Repair.
    #>
    [CmdletBinding()] param()
    $guidance = @'
Startup Repair must run from the Windows Recovery Environment (WinRE):
  1. Boot to WinRE (hold Shift while clicking Restart, or interrupt boot 3 times).
  2. Troubleshoot > Advanced options > Startup Repair.
To reboot directly into WinRE from an elevated session run:
  reagentc /boottore ; shutdown /r /t 0
'@
    Write-RTLog -Message 'Provided Startup Repair guidance.' -Level 'Info' -Category 'BootRepair'
    return $guidance
}

Export-ModuleMember -Function Test-RTWinRE, Get-RTBcdStore, Invoke-RTBootrec, Repair-RTBcd, Repair-RTEfiBootloader, Invoke-RTStartupRepairGuidance
