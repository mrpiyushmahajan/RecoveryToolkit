<#
.SYNOPSIS
    Download manager for the Windows Recovery Toolkit.
.DESCRIPTION
    Provides resilient downloads from official sources only, with resume support,
    retry logic, SHA256 verification, HTTPS validation, GitHub release resolution,
    parallel downloads and bandwidth-aware progress reporting.
#>

Set-StrictMode -Version Latest

# Fall back to a no-op logger if the launcher has not provided a global one.
if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}

function Test-RTUrlIsOfficial {
    <#
    .SYNOPSIS
        Validates that a URL uses HTTPS and belongs to a known official host.
    .PARAMETER Url
        The absolute URL to validate.
    .OUTPUTS
        [bool] True when the URL is HTTPS and its host is allow-listed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Url
    )

    $officialHosts = @(
        'aka.ms', 'download.microsoft.com', 'go.microsoft.com', 'learn.microsoft.com',
        'download.sysinternals.com', 'dotnet.microsoft.com', 'microsoft.com',
        'github.com', 'api.github.com', 'objects.githubusercontent.com', 'github-releases.githubusercontent.com',
        'sourceforge.net', 'downloads.sourceforge.net',
        'crystalmark.info', 'download.cpuid.com', 'cpuid.com', 'techpowerup.com',
        'hwinfo.com', 'sac.sk', 'voidtools.com', 'cgsecurity.org', 'ccleaner.com', 'download.ccleaner.com',
        'rufus.ie', 'ventoy.net', 'notepad-plus-plus.org', '7-zip.org', 'diskanalyzer.com',
        'windirstat.net', 'nirsoft.net', 'fastcopy.jp',
        'videolan.org', 'get.videolan.org', 'mozilla.org', 'download.mozilla.org',
        'google.com', 'dl.google.com', 'brave.com', 'laptop-updates.brave.com',
        'adobe.com', 'ardownload2.adobe.com', 'malwarebytes.com', 'downloads.malwarebytes.com',
        'anydesk.com', 'download.anydesk.com', 'teamviewer.com', 'download.teamviewer.com',
        'samsung.com', 'semiconductor.samsung.com', 'wdc.com', 'support.wdc.com',
        'crucial.com', 'kingston.com', 'amd.com', 'wagnardsoft.com'
    )

    try {
        $uri = [System.Uri]$Url
    } catch {
        Write-RTLog -Message "Malformed URL rejected: $Url" -Level 'Warning' -Category 'Download'
        return $false
    }

    if ($uri.Scheme -ne 'https') {
        Write-RTLog -Message "Non-HTTPS URL rejected: $Url" -Level 'Warning' -Category 'Download'
        return $false
    }

    $hostName = $uri.Host.ToLowerInvariant()
    foreach ($allowed in $officialHosts) {
        if ($hostName -eq $allowed -or $hostName.EndsWith(".$allowed")) {
            return $true
        }
    }

    Write-RTLog -Message "Host not on official allow-list, rejected: $hostName" -Level 'Warning' -Category 'Download'
    return $false
}

function Resolve-RTGitHubAsset {
    <#
    .SYNOPSIS
        Resolves the latest release asset download URL for a GitHub repository.
    .PARAMETER Repo
        Repository in 'owner/name' form.
    .PARAMETER AssetPattern
        Wildcard pattern matched against asset file names (e.g. 'rufus-*.exe').
    .OUTPUTS
        [pscustomobject] with Url, Name and Version, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$AssetPattern
    )

    $api = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $headers = @{ 'User-Agent' = 'RecoveryToolkit'; 'Accept' = 'application/vnd.github+json' }
        $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1
        if (-not $asset) {
            Write-RTLog -Message "No asset matching '$AssetPattern' in $Repo" -Level 'Warning' -Category 'Download'
            return $null
        }
        return [pscustomobject]@{
            Url     = $asset.browser_download_url
            Name    = $asset.name
            Version = $release.tag_name
        }
    } catch {
        Write-RTLog -Message "GitHub asset resolution failed for ${Repo}: $($_.Exception.Message)" -Level 'Error' -Category 'Download'
        return $null
    }
}

function Get-RTFileHash256 {
    <#
    .SYNOPSIS
        Computes the SHA256 hash of a file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-RTDownload {
    <#
    .SYNOPSIS
        Downloads a file from an official source with resume, retry and verification.
    .PARAMETER Url
        Source URL. Must pass Test-RTUrlIsOfficial unless -Force is specified.
    .PARAMETER Destination
        Full path to write the downloaded file.
    .PARAMETER ExpectedSha256
        Optional expected SHA256 to verify the completed download.
    .PARAMETER Retries
        Number of retry attempts on failure.
    .PARAMETER BandwidthLimitKBps
        Throttle in kilobytes/second. 0 disables throttling.
    .PARAMETER ProgressCallback
        Optional scriptblock invoked with (percent, downloadedBytes, totalBytes).
    .OUTPUTS
        [pscustomobject] Success, Path, Bytes, Sha256, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination,
        [string]$ExpectedSha256,
        [int]$Retries = 3,
        [int]$BandwidthLimitKBps = 0,
        [scriptblock]$ProgressCallback,
        [switch]$Force
    )

    if (-not $Force -and -not (Test-RTUrlIsOfficial -Url $Url)) {
        return [pscustomobject]@{ Success = $false; Path = $null; Bytes = 0; Sha256 = $null; Message = 'Rejected: source is not an official HTTPS host.' }
    }

    $dir = Split-Path -Path $Destination -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $partFile = "$Destination.part"

    for ($attempt = 1; $attempt -le [Math]::Max(1, $Retries); $attempt++) {
        Write-RTLog -Message "Downloading (attempt $attempt/$Retries): $Url" -Level 'Info' -Category 'Download'
        try {
            $existing = 0L
            if (Test-Path -LiteralPath $partFile) { $existing = (Get-Item -LiteralPath $partFile).Length }

            $request = [System.Net.HttpWebRequest]::Create($Url)
            $request.UserAgent = 'RecoveryToolkit'
            $request.Timeout = 60000
            $request.ReadWriteTimeout = 60000
            $request.AllowAutoRedirect = $true
            if ($existing -gt 0) { $request.AddRange([int64]$existing) }

            $response = $request.GetResponse()
            $total = $response.ContentLength + $existing
            $stream = $response.GetResponseStream()

            $mode = if ($existing -gt 0) { [System.IO.FileMode]::Append } else { [System.IO.FileMode]::Create }
            $fs = New-Object System.IO.FileStream($partFile, $mode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

            $buffer = New-Object byte[] 262144
            $downloaded = $existing
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $lastReport = 0

            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $read)
                $downloaded += $read

                if ($BandwidthLimitKBps -gt 0) {
                    $expectedMs = ($downloaded - $existing) / 1024.0 / $BandwidthLimitKBps * 1000.0
                    $delay = [int]($expectedMs - $sw.ElapsedMilliseconds)
                    if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
                }

                if ($ProgressCallback -and ($sw.ElapsedMilliseconds - $lastReport) -ge 200) {
                    $lastReport = $sw.ElapsedMilliseconds
                    $pct = if ($total -gt 0) { [int](($downloaded / $total) * 100) } else { -1 }
                    & $ProgressCallback $pct $downloaded $total
                }
            }

            $fs.Close(); $stream.Close(); $response.Close()

            if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
            Move-Item -LiteralPath $partFile -Destination $Destination -Force

            $hash = Get-RTFileHash256 -Path $Destination
            if ($ExpectedSha256 -and $hash -ne $ExpectedSha256) {
                Write-RTLog -Message "SHA256 mismatch for $Destination (expected $ExpectedSha256, got $hash)" -Level 'Error' -Category 'Download'
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                return [pscustomobject]@{ Success = $false; Path = $null; Bytes = 0; Sha256 = $hash; Message = 'SHA256 verification failed.' }
            }

            $bytes = (Get-Item -LiteralPath $Destination).Length
            Write-RTLog -Message "Download complete: $Destination ($([math]::Round($bytes/1MB,2)) MB)" -Level 'Info' -Category 'Download'
            return [pscustomobject]@{ Success = $true; Path = $Destination; Bytes = $bytes; Sha256 = $hash; Message = 'OK' }
        } catch {
            Write-RTLog -Message "Download attempt $attempt failed: $($_.Exception.Message)" -Level 'Warning' -Category 'Download'
            if ($attempt -ge $Retries) {
                return [pscustomobject]@{ Success = $false; Path = $null; Bytes = 0; Sha256 = $null; Message = $_.Exception.Message }
            }
            Start-Sleep -Seconds ([Math]::Min(30, [Math]::Pow(2, $attempt)))
        }
    }
}

function Invoke-RTParallelDownload {
    <#
    .SYNOPSIS
        Downloads multiple items concurrently using PowerShell 7 thread jobs.
    .PARAMETER Items
        Array of hashtables/objects with Url and Destination properties.
    .PARAMETER MaxParallel
        Maximum concurrent downloads.
    .OUTPUTS
        Array of result objects from Invoke-RTDownload.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [int]$MaxParallel = 3,
        [int]$Retries = 3,
        [int]$BandwidthLimitKBps = 0
    )

    $moduleRoot = $PSScriptRoot

    # ForEach-Object -Parallel is PowerShell 7+. Fall back to sequential on 5.1.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $results = $Items | ForEach-Object -ThrottleLimit $MaxParallel -Parallel {
            Import-Module (Join-Path $using:moduleRoot 'Download.psm1') -Force
            Invoke-RTDownload -Url $_.Url -Destination $_.Destination -Retries $using:Retries -BandwidthLimitKBps $using:BandwidthLimitKBps
        }
    } else {
        Write-RTLog -Message 'Parallel downloads require PowerShell 7; running sequentially.' -Level 'Info' -Category 'Download'
        $results = foreach ($item in $Items) {
            Invoke-RTDownload -Url $item.Url -Destination $item.Destination -Retries $Retries -BandwidthLimitKBps $BandwidthLimitKBps
        }
    }
    return $results
}

Export-ModuleMember -Function Test-RTUrlIsOfficial, Resolve-RTGitHubAsset, Get-RTFileHash256, Invoke-RTDownload, Invoke-RTParallelDownload
