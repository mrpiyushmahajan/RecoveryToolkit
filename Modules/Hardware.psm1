<#
.SYNOPSIS
    Hardware and system detection for the Windows Recovery Toolkit.
.DESCRIPTION
    Collects CPU, GPU, memory, motherboard, BIOS/UEFI, TPM, Secure Boot, disks,
    SMART health, battery wear, network adapters and OS details via CIM/WMI.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}

function Get-RTSafeCim {
    <#
    .SYNOPSIS
        Runs a CIM query and returns $null instead of throwing on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter
    )
    try {
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $params.Filter = $Filter }
        return Get-CimInstance @params
    } catch {
        Write-RTLog -Message "CIM query failed for $ClassName in ${Namespace}: $($_.Exception.Message)" -Level 'Warning' -Category 'Hardware'
        return $null
    }
}

function Get-RTProcessorInfo {
    [CmdletBinding()] param()
    $cpu = Get-RTSafeCim -ClassName Win32_Processor | Select-Object -First 1
    if (-not $cpu) { return $null }
    return [pscustomobject]@{
        Name          = $cpu.Name.Trim()
        Manufacturer  = $cpu.Manufacturer
        Cores         = $cpu.NumberOfCores
        LogicalCores  = $cpu.NumberOfLogicalProcessors
        MaxClockMHz   = $cpu.MaxClockSpeed
        Socket        = $cpu.SocketDesignation
        Architecture  = switch ($cpu.Architecture) { 0 {'x86'} 5 {'ARM'} 9 {'x64'} 12 {'ARM64'} default {"Arch$($cpu.Architecture)"} }
        Virtualization = $cpu.VirtualizationFirmwareEnabled
    }
}

function Get-RTMemoryInfo {
    [CmdletBinding()] param()
    $modules = Get-RTSafeCim -ClassName Win32_PhysicalMemory
    $cs = Get-RTSafeCim -ClassName Win32_ComputerSystem | Select-Object -First 1
    $sticks = @()
    if ($modules) {
        foreach ($m in $modules) {
            $sticks += [pscustomobject]@{
                Slot         = $m.DeviceLocator
                CapacityGB   = [math]::Round($m.Capacity / 1GB, 2)
                SpeedMHz     = $m.Speed
                Manufacturer = $m.Manufacturer
                PartNumber   = ($m.PartNumber).Trim()
                Type         = switch ($m.SMBIOSMemoryType) { 26 {'DDR4'} 34 {'DDR5'} 24 {'DDR3'} default {"Type$($m.SMBIOSMemoryType)"} }
            }
        }
    }
    return [pscustomobject]@{
        TotalGB = if ($cs) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
        Modules = $sticks
    }
}

function Get-RTGraphicsInfo {
    [CmdletBinding()] param()
    $gpus = Get-RTSafeCim -ClassName Win32_VideoController
    $result = @()
    if ($gpus) {
        foreach ($g in $gpus) {
            $result += [pscustomobject]@{
                Name          = $g.Name
                DriverVersion = $g.DriverVersion
                DriverDate    = $g.DriverDate
                VRAMMB        = if ($g.AdapterRAM) { [math]::Round($g.AdapterRAM / 1MB) } else { $null }
                Resolution    = if ($g.CurrentHorizontalResolution) { "$($g.CurrentHorizontalResolution)x$($g.CurrentVerticalResolution)" } else { $null }
            }
        }
    }
    return $result
}

function Get-RTFirmwareInfo {
    <#
    .SYNOPSIS
        Returns BIOS/UEFI, motherboard, TPM and Secure Boot state.
    #>
    [CmdletBinding()] param()
    $bios = Get-RTSafeCim -ClassName Win32_BIOS | Select-Object -First 1
    $board = Get-RTSafeCim -ClassName Win32_BaseBoard | Select-Object -First 1

    $secureBoot = $null
    try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $secureBoot = 'Unknown/Legacy' }

    $firmwareType = 'Unknown'
    try {
        $fw = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction Stop).PEFirmwareType
        $firmwareType = switch ($fw) { 1 {'Legacy BIOS'} 2 {'UEFI'} default {'Unknown'} }
    } catch {}

    $tpm = $null
    try {
        $t = Get-RTSafeCim -ClassName Win32_Tpm -Namespace 'root/cimv2/security/microsofttpm' | Select-Object -First 1
        if ($t) {
            $tpm = [pscustomobject]@{
                Present        = $true
                Enabled        = $t.IsEnabled_InitialValue
                Activated      = $t.IsActivated_InitialValue
                SpecVersion    = $t.SpecVersion
                Manufacturer   = $t.ManufacturerIdTxt
            }
        }
    } catch {}
    if (-not $tpm) { $tpm = [pscustomobject]@{ Present = $false } }

    return [pscustomobject]@{
        BiosVendor    = if ($bios) { $bios.Manufacturer } else { $null }
        BiosVersion   = if ($bios) { ($bios.SMBIOSBIOSVersion) } else { $null }
        BiosDate      = if ($bios) { $bios.ReleaseDate } else { $null }
        SerialNumber  = if ($bios) { $bios.SerialNumber } else { $null }
        Motherboard   = if ($board) { "$($board.Manufacturer) $($board.Product)" } else { $null }
        FirmwareType  = $firmwareType
        SecureBoot    = $secureBoot
        TPM           = $tpm
    }
}

function Get-RTDiskInfo {
    <#
    .SYNOPSIS
        Returns physical disks with type (NVMe/SSD/HDD), bus and SMART health.
    #>
    [CmdletBinding()] param()
    $result = @()
    try {
        $physical = Get-PhysicalDisk -ErrorAction Stop
        foreach ($d in $physical) {
            $reliability = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
            $result += [pscustomobject]@{
                FriendlyName   = $d.FriendlyName
                MediaType      = $d.MediaType
                BusType        = $d.BusType
                SizeGB         = [math]::Round($d.Size / 1GB, 2)
                HealthStatus   = $d.HealthStatus
                OperationalStatus = ($d.OperationalStatus -join ', ')
                Wear           = if ($reliability) { $reliability.Wear } else { $null }
                TemperatureC   = if ($reliability) { $reliability.Temperature } else { $null }
                PowerOnHours   = if ($reliability) { $reliability.PowerOnHours } else { $null }
                ReadErrors     = if ($reliability) { $reliability.ReadErrorsTotal } else { $null }
            }
        }
    } catch {
        Write-RTLog -Message "Get-PhysicalDisk failed, falling back to Win32_DiskDrive: $($_.Exception.Message)" -Level 'Warning' -Category 'Hardware'
        $disks = Get-RTSafeCim -ClassName Win32_DiskDrive
        if ($disks) {
            foreach ($d in $disks) {
                $result += [pscustomobject]@{
                    FriendlyName = $d.Model; MediaType = $d.MediaType; BusType = $d.InterfaceType
                    SizeGB = [math]::Round($d.Size / 1GB, 2); HealthStatus = $d.Status
                    OperationalStatus = $d.Status; Wear = $null; TemperatureC = $null
                    PowerOnHours = $null; ReadErrors = $null
                }
            }
        }
    }
    return $result
}

function Get-RTBatteryInfo {
    <#
    .SYNOPSIS
        Returns battery presence, charge and estimated wear from design vs full-charge capacity.
    #>
    [CmdletBinding()] param()
    $bat = Get-RTSafeCim -ClassName Win32_Battery | Select-Object -First 1
    if (-not $bat) { return [pscustomobject]@{ Present = $false } }

    $designCap = $null; $fullCap = $null; $wear = $null
    try {
        $static = Get-RTSafeCim -ClassName BatteryStaticData -Namespace 'root/wmi' | Select-Object -First 1
        $fullCharge = Get-RTSafeCim -ClassName BatteryFullChargedCapacity -Namespace 'root/wmi' | Select-Object -First 1
        if ($static -and $fullCharge) {
            $designCap = $static.DesignedCapacity
            $fullCap = $fullCharge.FullChargedCapacity
            if ($designCap -gt 0) { $wear = [math]::Round((1 - ($fullCap / $designCap)) * 100, 1) }
        }
    } catch {}

    return [pscustomobject]@{
        Present            = $true
        Name               = $bat.Name
        ChargePercent      = $bat.EstimatedChargeRemaining
        Status             = switch ($bat.BatteryStatus) { 1 {'Discharging'} 2 {'On AC'} default {"Status$($bat.BatteryStatus)"} }
        DesignCapacitymWh  = $designCap
        FullChargeCapmWh   = $fullCap
        WearPercent        = $wear
    }
}

function Get-RTNetworkInfo {
    [CmdletBinding()] param()
    $result = @()
    $adapters = Get-RTSafeCim -ClassName Win32_NetworkAdapter -Filter 'PhysicalAdapter=True'
    if ($adapters) {
        foreach ($a in $adapters) {
            $result += [pscustomobject]@{
                Name        = $a.Name
                MACAddress  = $a.MACAddress
                Type        = if ($a.Name -match 'Wi-?Fi|Wireless|802\.11') { 'Wi-Fi' } elseif ($a.Name -match 'Bluetooth') { 'Bluetooth' } else { 'Ethernet' }
                Speed       = if ($a.Speed) { "$([math]::Round($a.Speed/1MB)) Mbps" } else { $null }
                Enabled     = $a.NetEnabled
            }
        }
    }
    return $result
}

function Get-RTOSInfo {
    [CmdletBinding()] param()
    $os = Get-RTSafeCim -ClassName Win32_OperatingSystem | Select-Object -First 1
    $cs = Get-RTSafeCim -ClassName Win32_ComputerSystem | Select-Object -First 1
    return [pscustomobject]@{
        Caption       = if ($os) { $os.Caption } else { $null }
        Version       = if ($os) { $os.Version } else { $null }
        Build         = if ($os) { $os.BuildNumber } else { $null }
        Architecture  = if ($os) { $os.OSArchitecture } else { $null }
        InstallDate   = if ($os) { $os.InstallDate } else { $null }
        LastBoot      = if ($os) { $os.LastBootUpTime } else { $null }
        Manufacturer  = if ($cs) { $cs.Manufacturer } else { $null }
        Model         = if ($cs) { $cs.Model } else { $null }
        Hostname      = if ($cs) { $cs.Name } else { $null }
    }
}

function Get-RTFullHardwareReport {
    <#
    .SYNOPSIS
        Aggregates every hardware/system detail into a single object.
    .OUTPUTS
        [pscustomobject] with nested OS, CPU, Memory, GPU, Firmware, Disks, Battery, Network.
    #>
    [CmdletBinding()] param()
    Write-RTLog -Message 'Collecting full hardware report.' -Level 'Info' -Category 'Hardware'
    return [pscustomobject]@{
        CollectedAt = (Get-Date)
        OS          = Get-RTOSInfo
        CPU         = Get-RTProcessorInfo
        Memory      = Get-RTMemoryInfo
        GPU         = Get-RTGraphicsInfo
        Firmware    = Get-RTFirmwareInfo
        Disks       = Get-RTDiskInfo
        Battery     = Get-RTBatteryInfo
        Network     = Get-RTNetworkInfo
    }
}

Export-ModuleMember -Function Get-RTProcessorInfo, Get-RTMemoryInfo, Get-RTGraphicsInfo,
    Get-RTFirmwareInfo, Get-RTDiskInfo, Get-RTBatteryInfo, Get-RTNetworkInfo, Get-RTOSInfo, Get-RTFullHardwareReport
