<#
.SYNOPSIS
    Self-update system for the Recovery Toolkit.
.DESCRIPTION
    Checks GitHub releases for a newer toolkit version, downloads the release
    package, and updates the toolkit files in place while preserving user data
    folders (Downloads, Drivers, Logs, Reports, Cache).
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}
if (-not (Get-Command -Name Invoke-RTDownload -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Download.psm1') -Force
}

function Compare-RTVersion {
    <#
    .SYNOPSIS
        Compares two version strings; returns 1 if Remote > Local, 0 if equal, -1 otherwise.
    #>
    [CmdletBinding()]
    param([string]$Local, [string]$Remote)
    try {
        $l = [version]($Local -replace '[^\d\.]', '')
        $r = [version]($Remote -replace '[^\d\.]', '')
        return $r.CompareTo($l)
    } catch { return 0 }
}

function Test-RTUpdateAvailable {
    <#
    .SYNOPSIS
        Queries the GitHub releases API and reports whether a newer version exists.
    .PARAMETER Repo
        Repository in owner/name form.
    .PARAMETER CurrentVersion
        The installed toolkit version.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$CurrentVersion
    )
    try {
        $headers = @{ 'User-Agent' = 'RecoveryToolkit'; 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -TimeoutSec 30
        $remote = $release.tag_name
        $cmp = Compare-RTVersion -Local $CurrentVersion -Remote $remote
        $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
        return [pscustomobject]@{
            UpdateAvailable = ($cmp -gt 0)
            CurrentVersion  = $CurrentVersion
            LatestVersion   = $remote
            DownloadUrl     = if ($asset) { $asset.browser_download_url } else { $release.zipball_url }
            Notes           = $release.body
        }
    } catch {
        Write-RTLog -Message "Update check failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Update'
        return [pscustomobject]@{ UpdateAvailable = $false; CurrentVersion = $CurrentVersion; LatestVersion = $CurrentVersion; DownloadUrl = $null; Notes = $null }
    }
}

function Invoke-RTSelfUpdate {
    <#
    .SYNOPSIS
        Downloads and applies a toolkit update, backing up the current version.
    .PARAMETER DownloadUrl
        Release zip URL (validated as official by the Download module).
    .PARAMETER ToolkitRoot
        Root folder of the installed toolkit.
    .PARAMETER CacheRoot
        Folder for the downloaded update package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$ToolkitRoot,
        [Parameter(Mandatory)][string]$CacheRoot
    )
    $pkg = Join-Path $CacheRoot 'update.zip'
    $result = Invoke-RTDownload -Url $DownloadUrl -Destination $pkg
    if (-not $result.Success) { return [pscustomobject]@{ Success = $false; Message = $result.Message } }

    $extract = Join-Path $CacheRoot 'update_extract'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive -Path $pkg -DestinationPath $extract -Force

    # GitHub zipballs nest content one level deep; detect the real root.
    $srcRoot = $extract
    $inner = Get-ChildItem $extract -Directory
    if ($inner.Count -eq 1 -and -not (Test-Path (Join-Path $extract 'Launcher.ps1'))) { $srcRoot = $inner[0].FullName }

    # Only overwrite code/config; never touch user data folders.
    $preserve = @('Downloads', 'Drivers', 'Logs', 'Reports', 'Cache', 'Portable', 'Installers')
    $backup = Join-Path $CacheRoot ("backup_" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    try {
        Get-ChildItem $srcRoot -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\','/')
            $top = ($rel -split '[\\/]')[0]
            if ($preserve -contains $top) { return }
            $target = Join-Path $ToolkitRoot $rel
            $targetDir = Split-Path $target -Parent
            if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
            if (Test-Path $target) { Copy-Item $target -Destination (Join-Path $backup $rel) -Force -ErrorAction SilentlyContinue }
            Copy-Item $_.FullName -Destination $target -Force
        }
        Write-RTLog -Message "Self-update applied. Backup at $backup" -Level 'Info' -Category 'Update'
        return [pscustomobject]@{ Success = $true; Message = 'Update applied. Restart the toolkit.'; Backup = $backup }
    } catch {
        Write-RTLog -Message "Self-update failed: $($_.Exception.Message)" -Level 'Error' -Category 'Update'
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.Message }
    }
}

Export-ModuleMember -Function Compare-RTVersion, Test-RTUpdateAvailable, Invoke-RTSelfUpdate
