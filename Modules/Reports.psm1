<#
.SYNOPSIS
    Report generation for the Recovery Toolkit.
.DESCRIPTION
    Produces styled HTML, JSON and CSV reports from hardware, driver, software,
    activation and diagnostics data collected by the other modules.
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}

function ConvertTo-RTHtmlSection {
    <#
    .SYNOPSIS
        Renders an object or array into an HTML table under a titled section.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowNull()]$Data
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<section><h2>$([System.Web.HttpUtility]::HtmlEncode($Title))</h2>")
    if ($null -eq $Data) {
        [void]$sb.Append('<p class="muted">No data.</p></section>')
        return $sb.ToString()
    }

    if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
        $items = @($Data)
        if ($items.Count -eq 0) { [void]$sb.Append('<p class="muted">None.</p></section>'); return $sb.ToString() }
        $props = $items[0].PSObject.Properties.Name
        [void]$sb.Append('<table><thead><tr>')
        foreach ($p in $props) { [void]$sb.Append("<th>$([System.Web.HttpUtility]::HtmlEncode($p))</th>") }
        [void]$sb.Append('</tr></thead><tbody>')
        foreach ($row in $items) {
            [void]$sb.Append('<tr>')
            foreach ($p in $props) {
                $val = [string]$row.$p
                [void]$sb.Append("<td>$([System.Web.HttpUtility]::HtmlEncode($val))</td>")
            }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append('</tbody></table>')
    } else {
        [void]$sb.Append('<table><tbody>')
        foreach ($prop in $Data.PSObject.Properties) {
            $val = if ($prop.Value -is [System.Collections.IEnumerable] -and $prop.Value -isnot [string]) { '(see nested)' } else { [string]$prop.Value }
            [void]$sb.Append("<tr><th>$([System.Web.HttpUtility]::HtmlEncode($prop.Name))</th><td>$([System.Web.HttpUtility]::HtmlEncode($val))</td></tr>")
        }
        [void]$sb.Append('</tbody></table>')
    }
    [void]$sb.Append('</section>')
    return $sb.ToString()
}

function New-RTHtmlReport {
    <#
    .SYNOPSIS
        Writes a dark-themed HTML system report from a hashtable of named sections.
    .PARAMETER Sections
        Ordered hashtable of Title -> data object/array.
    .PARAMETER Path
        Output .html path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Sections,
        [Parameter(Mandatory)][string]$Path
    )
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $body = [System.Text.StringBuilder]::new()
    foreach ($title in $Sections.Keys) {
        [void]$body.Append((ConvertTo-RTHtmlSection -Title $title -Data $Sections[$title]))
    }

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Recovery Toolkit Report</title>
<style>
:root{color-scheme:dark}
body{font-family:'Segoe UI',system-ui,sans-serif;background:#12141a;color:#e6e8ee;margin:0;padding:2rem;line-height:1.5}
h1{font-size:1.6rem;margin:0 0 .25rem} .stamp{color:#8b93a7;margin-bottom:2rem}
section{background:#1b1e27;border:1px solid #2a2f3d;border-radius:12px;padding:1.25rem 1.5rem;margin-bottom:1.5rem}
h2{font-size:1.1rem;margin:0 0 .75rem;color:#7aa2ff}
table{width:100%;border-collapse:collapse;font-size:.9rem}
th,td{text-align:left;padding:.5rem .75rem;border-bottom:1px solid #262b38;vertical-align:top}
thead th{color:#9aa4bd;font-weight:600;text-transform:uppercase;font-size:.72rem;letter-spacing:.04em}
tbody th{color:#9aa4bd;font-weight:600;width:30%}
.muted{color:#8b93a7} a{color:#7aa2ff}
</style></head><body>
<h1>Windows Recovery Toolkit — System Report</h1>
<div class="stamp">Generated $generated on $($env:COMPUTERNAME)</div>
$($body.ToString())
</body></html>
"@
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $html | Out-File -FilePath $Path -Encoding utf8
    Write-RTLog -Message "HTML report written: $Path" -Level 'Info' -Category 'Reports'
    return $Path
}

function New-RTJsonReport {
    <#
    .SYNOPSIS
        Serializes a data object to a JSON report file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Data | ConvertTo-Json -Depth 8 | Out-File -FilePath $Path -Encoding utf8
    Write-RTLog -Message "JSON report written: $Path" -Level 'Info' -Category 'Reports'
    return $Path
}

function New-RTCsvReport {
    <#
    .SYNOPSIS
        Writes a collection to a CSV report file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Path
    )
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
    Write-RTLog -Message "CSV report written: $Path" -Level 'Info' -Category 'Reports'
    return $Path
}

function Get-RTInstalledSoftware {
    <#
    .SYNOPSIS
        Returns installed software from the uninstall registry keys (64/32-bit).
    #>
    [CmdletBinding()] param()
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = foreach ($k in $keys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object @{N='Name';E={$_.DisplayName}}, @{N='Version';E={$_.DisplayVersion}}, Publisher, InstallDate
    }
    return $apps | Sort-Object Name -Unique
}

Export-ModuleMember -Function New-RTHtmlReport, New-RTJsonReport, New-RTCsvReport, Get-RTInstalledSoftware, ConvertTo-RTHtmlSection
