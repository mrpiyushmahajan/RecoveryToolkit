<#
.SYNOPSIS
    Driver backup, restore and inventory for the Recovery Toolkit.
.DESCRIPTION
    Uses DISM and pnputil to export/import third-party drivers, list installed
    drivers, and detect devices missing drivers.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}
if (-not (Get-Command -Name Invoke-RTProcess -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Repair.psm1') -Force
}

function Backup-RTDrivers {
    <#
    .SYNOPSIS
        Exports all third-party drivers to a destination folder using DISM.
    .PARAMETER Destination
        Target folder for exported drivers.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    $stamp = Join-Path $Destination ("DriverBackup_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $stamp -Force | Out-Null
    Write-RTLog -Message "Exporting drivers to $stamp" -Level 'Info' -Category 'Drivers'
    $result = Invoke-RTProcess -FilePath 'dism.exe' -Arguments '/online','/export-driver',"/destination:$stamp"
    $result | Add-Member -NotePropertyName 'Path' -NotePropertyValue $stamp -PassThru
    return $result
}

function Restore-RTDrivers {
    <#
    .SYNOPSIS
        Installs all .inf drivers found under a source folder using pnputil.
    .PARAMETER Source
        Folder containing previously exported drivers.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Source)
    if (-not (Test-Path $Source)) {
        Write-RTLog -Message "Driver source not found: $Source" -Level 'Error' -Category 'Drivers'
        return [pscustomobject]@{ Success = $false; Output = "Source not found: $Source" }
    }
    Write-RTLog -Message "Restoring drivers from $Source" -Level 'Info' -Category 'Drivers'
    return Invoke-RTProcess -FilePath 'pnputil.exe' -Arguments '/add-driver',"$Source\*.inf",'/subdirs','/install' -SuccessCodes @(0, 3010, 259)
}

function Get-RTInstalledDrivers {
    <#
    .SYNOPSIS
        Returns installed third-party drivers with provider, version and date.
    #>
    [CmdletBinding()] param()
    try {
        return Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceName } |
            Select-Object DeviceName, DriverProviderName, DriverVersion, DriverDate, InfName, DeviceClass |
            Sort-Object DeviceClass, DeviceName
    } catch {
        Write-RTLog -Message "Driver inventory failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Drivers'
        return @()
    }
}

function Get-RTMissingDrivers {
    <#
    .SYNOPSIS
        Returns devices with an error state (missing/failed drivers).
    #>
    [CmdletBinding()] param()
    try {
        return Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
            Select-Object Name, DeviceID, @{N='ErrorCode';E={$_.ConfigManagerErrorCode}}, Status
    } catch {
        Write-RTLog -Message "Missing-driver scan failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Drivers'
        return @()
    }
}

function Get-RTDriverVendorPage {
    <#
    .SYNOPSIS
        Maps a system manufacturer to its official driver/support page.
    #>
    [CmdletBinding()] param()
    $mfg = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer
    $map = @{
        'Dell'     = 'https://www.dell.com/support/home'
        'HP'       = 'https://support.hp.com/us-en/drivers'
        'Hewlett-Packard' = 'https://support.hp.com/us-en/drivers'
        'Lenovo'   = 'https://support.lenovo.com/solutions/ht003029'
        'ASUS'     = 'https://www.asus.com/support/'
        'ASUSTeK'  = 'https://www.asus.com/support/'
        'Acer'     = 'https://www.acer.com/us-en/support'
        'MSI'      = 'https://www.msi.com/support/download'
        'Microsoft'= 'https://support.microsoft.com/surface'
        'Samsung'  = 'https://www.samsung.com/us/support/downloads/'
    }
    foreach ($key in $map.Keys) {
        if ($mfg -and $mfg -like "*$key*") { return [pscustomobject]@{ Manufacturer = $mfg; Url = $map[$key] } }
    }
    return [pscustomobject]@{ Manufacturer = $mfg; Url = 'https://www.google.com/search?q=' + [uri]::EscapeDataString("$mfg drivers support") }
}

Export-ModuleMember -Function Backup-RTDrivers, Restore-RTDrivers, Get-RTInstalledDrivers, Get-RTMissingDrivers, Get-RTDriverVendorPage
