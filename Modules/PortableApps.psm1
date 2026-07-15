<#
.SYNOPSIS
    Portable application and installer management for the Recovery Toolkit.
.DESCRIPTION
    Downloads, extracts and organizes portable tools and installers defined in
    config.json using the Download module, resolving GitHub release assets where
    configured. Supports launching already-downloaded portable tools.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}
if (-not (Get-Command -Name Invoke-RTDownload -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Download.psm1') -Force
}

function Resolve-RTAppUrl {
    <#
    .SYNOPSIS
        Resolves the effective download URL for a catalog entry, expanding GitHub releases.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$App)
    if ($App.PSObject.Properties.Name -contains 'githubRepo' -and $App.githubRepo) {
        $asset = Resolve-RTGitHubAsset -Repo $App.githubRepo -AssetPattern $App.assetPattern
        if ($asset) { return $asset.Url }
        Write-RTLog -Message "Falling back to release page for $($App.name)" -Level 'Warning' -Category 'PortableApps'
    }
    return $App.download
}

function Get-RTPortableApp {
    <#
    .SYNOPSIS
        Downloads and, for zips, extracts a single portable app into the Portable folder.
    .PARAMETER App
        Catalog entry object from config.json.
    .PARAMETER PortableRoot
        Root folder for portable tools.
    .PARAMETER DownloadRoot
        Root folder for raw downloads.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$PortableRoot,
        [Parameter(Mandatory)][string]$DownloadRoot,
        [scriptblock]$ProgressCallback
    )
    # Some tools have no stable direct link (page-gated or POST downloads).
    # Open their official page so the user can grab it manually — never a failure.
    if (($App.PSObject.Properties.Name -contains 'openPage') -and $App.openPage) {
        Write-RTLog -Message "$($App.name) has no stable direct download; opening its official page." -Level 'Info' -Category 'PortableApps'
        Start-Process $App.download
        return [pscustomobject]@{ Id = $App.id; Success = $true; OpenedPage = $true; Message = "Opened official page for $($App.name)." }
    }

    $url = Resolve-RTAppUrl -App $App
    if (-not $url) { return [pscustomobject]@{ Id = $App.id; Success = $false; Message = 'No download URL.' } }

    $ext = switch ($App.type) { 'zip' {'zip'} 'msi' {'msi'} default {'exe'} }
    $dest = Join-Path $DownloadRoot "$($App.id).$ext"

    $result = Invoke-RTDownload -Url $url -Destination $dest -ProgressCallback $ProgressCallback
    if (-not $result.Success) {
        return [pscustomobject]@{ Id = $App.id; Success = $false; Message = $result.Message }
    }

    $appDir = Join-Path $PortableRoot $App.id
    if ($App.type -eq 'zip') {
        try {
            if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }
            Expand-Archive -Path $dest -DestinationPath $appDir -Force
            Write-RTLog -Message "Extracted $($App.name) to $appDir" -Level 'Info' -Category 'PortableApps'
        } catch {
            Write-RTLog -Message "Extraction failed for $($App.name): $($_.Exception.Message)" -Level 'Error' -Category 'PortableApps'
            return [pscustomobject]@{ Id = $App.id; Success = $false; Message = "Extract failed: $($_.Exception.Message)" }
        }
    } else {
        if (-not (Test-Path $appDir)) { New-Item -ItemType Directory -Path $appDir -Force | Out-Null }
        Copy-Item $dest -Destination (Join-Path $appDir (Split-Path $dest -Leaf)) -Force
    }

    return [pscustomobject]@{ Id = $App.id; Success = $true; Path = $appDir; Message = 'OK' }
}

function Get-RTAllPortableApps {
    <#
    .SYNOPSIS
        Downloads every enabled portable app from the catalog.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Catalog,
        [Parameter(Mandatory)][string]$PortableRoot,
        [Parameter(Mandatory)][string]$DownloadRoot,
        [scriptblock]$StatusCallback
    )
    $results = @()
    foreach ($app in $Catalog) {
        if ($StatusCallback) { & $StatusCallback "Downloading $($app.name)..." }
        $results += Get-RTPortableApp -App $app -PortableRoot $PortableRoot -DownloadRoot $DownloadRoot
    }
    return $results
}

function Find-RTPortableExe {
    <#
    .SYNOPSIS
        Locates a portable app's main executable, searching recursively as a fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$PortableRoot
    )
    $appDir = Join-Path $PortableRoot $App.id
    if (-not (Test-Path $appDir)) { return $null }
    $direct = Join-Path $appDir $App.exe
    if (Test-Path $direct) { return $direct }
    $found = Get-ChildItem -Path $appDir -Filter $App.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Start-RTPortableApp {
    <#
    .SYNOPSIS
        Launches a previously downloaded portable app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$PortableRoot
    )
    $exe = Find-RTPortableExe -App $App -PortableRoot $PortableRoot
    if (-not $exe) {
        Write-RTLog -Message "$($App.name) is not downloaded yet." -Level 'Warning' -Category 'PortableApps'
        return $false
    }
    Start-Process -FilePath $exe
    Write-RTLog -Message "Launched $($App.name)" -Level 'Info' -Category 'PortableApps'
    return $true
}

function Install-RTApplication {
    <#
    .SYNOPSIS
        Downloads and silently runs an installer catalog entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Installer,
        [Parameter(Mandatory)][string]$InstallerRoot,
        [switch]$Silent
    )
    if (($Installer.PSObject.Properties.Name -contains 'openPage') -and $Installer.openPage) {
        Write-RTLog -Message "$($Installer.name) has no stable direct installer link; opening its official page." -Level 'Info' -Category 'PortableApps'
        Start-Process $Installer.download
        return [pscustomobject]@{ Id = $Installer.id; Success = $true; OpenedPage = $true; Message = "Opened official page for $($Installer.name)." }
    }

    $ext = if ($Installer.download -match '\.msi(\?|$)') { 'msi' } else { 'exe' }
    $dest = Join-Path $InstallerRoot "$($Installer.id).$ext"
    $result = Invoke-RTDownload -Url $Installer.download -Destination $dest
    if (-not $result.Success) { return [pscustomobject]@{ Id = $Installer.id; Success = $false; Message = $result.Message } }

    if ($Silent) {
        try {
            if ($ext -eq 'msi') {
                Start-Process 'msiexec.exe' -ArgumentList "/i `"$dest`" $($Installer.silentArgs)" -Wait
            } else {
                Start-Process -FilePath $dest -ArgumentList $Installer.silentArgs -Wait
            }
            Write-RTLog -Message "Installed $($Installer.name)" -Level 'Info' -Category 'PortableApps'
            return [pscustomobject]@{ Id = $Installer.id; Success = $true; Message = 'Installed' }
        } catch {
            return [pscustomobject]@{ Id = $Installer.id; Success = $false; Message = $_.Exception.Message }
        }
    }
    Start-Process -FilePath $dest
    return [pscustomobject]@{ Id = $Installer.id; Success = $true; Message = 'Launched installer' }
}

Export-ModuleMember -Function Resolve-RTAppUrl, Get-RTPortableApp, Get-RTAllPortableApps, Find-RTPortableExe, Start-RTPortableApp, Install-RTApplication
