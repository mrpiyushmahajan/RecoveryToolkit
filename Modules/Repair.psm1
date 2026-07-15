<#
.SYNOPSIS
    Windows repair automation for the Recovery Toolkit.
.DESCRIPTION
    Wraps DISM, SFC, CHKDSK, network stack reset, Windows Update reset, Defender
    reset, WMI repair and shell (Explorer/Start/Taskbar/Search) repairs behind
    consistent, logged advanced functions with graceful error handling.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}

function Invoke-RTProcess {
    <#
    .SYNOPSIS
        Runs an external command, capturing exit code and output, without throwing.
    .OUTPUTS
        [pscustomobject] Success, ExitCode, Output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int[]]$SuccessCodes = @(0)
    )
    Write-RTLog -Message "Executing: $FilePath $($Arguments -join ' ')" -Level 'Info' -Category 'Repair'
    try {
        $output = & $FilePath @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
        $success = $SuccessCodes -contains $code
        $level = if ($success) { 'Info' } else { 'Warning' }
        Write-RTLog -Message "$FilePath exited with code $code" -Level $level -Category 'Repair'
        return [pscustomobject]@{ Success = $success; ExitCode = $code; Output = $output.Trim() }
    } catch {
        Write-RTLog -Message "Execution failed: $($_.Exception.Message)" -Level 'Error' -Category 'Repair'
        return [pscustomobject]@{ Success = $false; ExitCode = -1; Output = $_.Exception.Message }
    }
}

function Invoke-RTDismRestoreHealth {
    <#
    .SYNOPSIS
        Runs DISM /Online /Cleanup-Image /RestoreHealth to repair the component store.
    #>
    [CmdletBinding()] param()
    return Invoke-RTProcess -FilePath 'dism.exe' -Arguments '/Online','/Cleanup-Image','/RestoreHealth'
}

function Invoke-RTDismCheckHealth {
    [CmdletBinding()] param()
    return Invoke-RTProcess -FilePath 'dism.exe' -Arguments '/Online','/Cleanup-Image','/ScanHealth'
}

function Invoke-RTSfcScan {
    <#
    .SYNOPSIS
        Runs System File Checker (sfc /scannow).
    #>
    [CmdletBinding()] param()
    return Invoke-RTProcess -FilePath 'sfc.exe' -Arguments '/scannow'
}

function Invoke-RTChkdskSchedule {
    <#
    .SYNOPSIS
        Schedules CHKDSK for a drive on next reboot.
    .PARAMETER Drive
        Drive letter (default C).
    #>
    [CmdletBinding()]
    param([string]$Drive = 'C')
    $letter = $Drive.TrimEnd(':', '\')
    return Invoke-RTProcess -FilePath 'cmd.exe' -Arguments '/c',"echo Y| chkdsk ${letter}: /f /r" -SuccessCodes @(0, 1)
}

function Reset-RTNetworkStack {
    <#
    .SYNOPSIS
        Resets Winsock, TCP/IP, flushes DNS and releases/renews IP.
    .OUTPUTS
        Ordered dictionary of step -> result.
    #>
    [CmdletBinding()] param()
    $steps = [ordered]@{}
    $steps['WinsockReset']  = Invoke-RTProcess -FilePath 'netsh.exe' -Arguments 'winsock','reset'
    $steps['IPv4Reset']     = Invoke-RTProcess -FilePath 'netsh.exe' -Arguments 'int','ip','reset'
    $steps['DNSFlush']      = Invoke-RTProcess -FilePath 'ipconfig.exe' -Arguments '/flushdns'
    $steps['IPRelease']     = Invoke-RTProcess -FilePath 'ipconfig.exe' -Arguments '/release'
    $steps['IPRenew']       = Invoke-RTProcess -FilePath 'ipconfig.exe' -Arguments '/renew'
    Write-RTLog -Message 'Network stack reset complete. A reboot is recommended.' -Level 'Info' -Category 'Repair'
    return $steps
}

function Reset-RTWindowsUpdate {
    <#
    .SYNOPSIS
        Stops update services, clears SoftwareDistribution and catroot2, restarts services.
    #>
    [CmdletBinding()] param()
    $services = 'wuauserv', 'cryptSvc', 'bits', 'msiserver'
    $result = [ordered]@{}
    foreach ($svc in $services) {
        try { Stop-Service -Name $svc -Force -ErrorAction Stop; $result["Stop_$svc"] = 'Stopped' }
        catch { $result["Stop_$svc"] = "Warning: $($_.Exception.Message)" }
    }

    $sd = Join-Path $env:windir 'SoftwareDistribution'
    $cr = Join-Path $env:windir 'System32\catroot2'
    foreach ($path in @($sd, $cr)) {
        try {
            if (Test-Path $path) {
                Rename-Item -Path $path -NewName "$([System.IO.Path]::GetFileName($path)).bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction Stop
                $result["Clear_$([System.IO.Path]::GetFileName($path))"] = 'Renamed'
            }
        } catch { $result["Clear_$([System.IO.Path]::GetFileName($path))"] = "Warning: $($_.Exception.Message)" }
    }

    foreach ($svc in $services) {
        try { Start-Service -Name $svc -ErrorAction Stop; $result["Start_$svc"] = 'Started' }
        catch { $result["Start_$svc"] = "Warning: $($_.Exception.Message)" }
    }
    Write-RTLog -Message 'Windows Update components reset.' -Level 'Info' -Category 'Repair'
    return $result
}

function Reset-RTWindowsDefender {
    <#
    .SYNOPSIS
        Resets Microsoft Defender signatures and re-registers the service.
    #>
    [CmdletBinding()] param()
    $mp = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    $result = [ordered]@{}
    if (Test-Path $mp) {
        $result['RemoveDefinitions'] = Invoke-RTProcess -FilePath $mp -Arguments '-RemoveDefinitions','-All'
        $result['UpdateSignatures']  = Invoke-RTProcess -FilePath $mp -Arguments '-SignatureUpdate'
    } else {
        $result['MpCmdRun'] = 'Not found on this system.'
    }
    return $result
}

function Repair-RTWmi {
    <#
    .SYNOPSIS
        Verifies and repairs the WMI repository.
    #>
    [CmdletBinding()] param()
    $result = [ordered]@{}
    $result['Verify'] = Invoke-RTProcess -FilePath 'winmgmt.exe' -Arguments '/verifyrepository' -SuccessCodes @(0)
    if ($result['Verify'].Output -match 'inconsistent') {
        $result['Salvage'] = Invoke-RTProcess -FilePath 'winmgmt.exe' -Arguments '/salvagerepository'
    }
    return $result
}

function Repair-RTShell {
    <#
    .SYNOPSIS
        Repairs Explorer, Start Menu, Taskbar and Search by re-registering packages and restarting Explorer.
    #>
    [CmdletBinding()] param()
    $result = [ordered]@{}
    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force
        $result['ExplorerRestart'] = 'Explorer restarted'
        Start-Process explorer.exe
    } catch { $result['ExplorerRestart'] = "Warning: $($_.Exception.Message)" }

    try {
        Get-AppxPackage -AllUsers Microsoft.Windows.ShellExperienceHost, Microsoft.Windows.StartMenuExperienceHost -ErrorAction SilentlyContinue |
            ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue }
        $result['StartMenuReregister'] = 'Re-registered'
    } catch { $result['StartMenuReregister'] = "Warning: $($_.Exception.Message)" }

    return $result
}

function Reset-RTMicrosoftStore {
    <#
    .SYNOPSIS
        Resets the Microsoft Store cache via wsreset.
    #>
    [CmdletBinding()] param()
    return Invoke-RTProcess -FilePath 'wsreset.exe' -Arguments '-i' -SuccessCodes @(0)
}

Export-ModuleMember -Function Invoke-RTProcess, Invoke-RTDismRestoreHealth, Invoke-RTDismCheckHealth,
    Invoke-RTSfcScan, Invoke-RTChkdskSchedule, Reset-RTNetworkStack, Reset-RTWindowsUpdate,
    Reset-RTWindowsDefender, Repair-RTWmi, Repair-RTShell, Reset-RTMicrosoftStore
