<#
.SYNOPSIS
    Windows Forms dark-mode GUI for the Recovery Toolkit.
.DESCRIPTION
    Renders a modern dark interface with a searchable, category-filtered action
    grid, toolbar, progress bar, status bar and live log. Actions run on a
    background runspace so the UI stays responsive; status and log updates are
    marshalled back to the UI thread via a synchronized state object and a timer.
#>

Set-StrictMode -Version Latest

# Load GUI assemblies at import time so type literals below resolve on both
# Windows PowerShell 5.1 (no auto-load) and PowerShell 7.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not (Get-Command -Name Write-RTLog -ErrorAction SilentlyContinue)) {
    function Write-RTLog { param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General') Write-Verbose "[$Level] $Message" }
}

# --- Dark theme palette -----------------------------------------------------
$script:RTTheme = @{
    Background = [System.Drawing.Color]::FromArgb(18, 20, 26)
    Surface    = [System.Drawing.Color]::FromArgb(27, 30, 39)
    Surface2   = [System.Drawing.Color]::FromArgb(34, 38, 49)
    Border     = [System.Drawing.Color]::FromArgb(42, 47, 61)
    Accent     = [System.Drawing.Color]::FromArgb(122, 162, 255)
    AccentDark = [System.Drawing.Color]::FromArgb(64, 92, 168)
    Text       = [System.Drawing.Color]::FromArgb(230, 232, 238)
    TextMuted  = [System.Drawing.Color]::FromArgb(139, 147, 167)
    Success    = [System.Drawing.Color]::FromArgb(94, 196, 128)
    Warning    = [System.Drawing.Color]::FromArgb(232, 178, 84)
    Danger     = [System.Drawing.Color]::FromArgb(228, 108, 108)
}

function New-RTFlatButton {
    <#
    .SYNOPSIS
        Creates a themed flat button.
    #>
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$Width = 120,
        [int]$Height = 32,
        [System.Drawing.Color]$Back = $script:RTTheme.Surface2,
        [System.Drawing.Color]$Fore = $script:RTTheme.Text
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Width = $Width; $b.Height = $Height
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $script:RTTheme.Border
    $b.FlatAppearance.BorderSize = 1
    $b.BackColor = $Back
    $b.ForeColor = $Fore
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.TextAlign = 'MiddleLeft'
    $b.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    return $b
}

function Show-RTMainWindow {
    <#
    .SYNOPSIS
        Builds and shows the toolkit's main window.
    .PARAMETER Context
        Hashtable with keys: Config, Root, Paths, Actions, Categories, HardwareSummary.
        Actions is an array of objects: Name, Category, Description, Script (scriptblock).
    .PARAMETER RenderPngPath
        Optional. When set, the window is laid out off-screen, captured to this
        PNG path and closed immediately instead of running interactively. Used
        for automated verification and documentation screenshots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [string]$RenderPngPath
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $theme = $script:RTTheme

    # --- Shared state for background execution -----------------------------
    $sync = [hashtable]::Synchronized(@{
        Running   = $false
        Status    = 'Ready'
        Progress  = 0
        LogQueue  = [System.Collections.Queue]::Synchronized([System.Collections.Queue]::new())
    })

    # --- Root form ---------------------------------------------------------
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$($Context.Config.toolkit.name) v$($Context.Config.toolkit.version)"
    $form.Size = New-Object System.Drawing.Size(1080, 720)
    $form.MinimumSize = New-Object System.Drawing.Size(900, 600)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = $theme.Background
    $form.ForeColor = $theme.Text
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    # --- Toolbar (top) -----------------------------------------------------
    $toolbar = New-Object System.Windows.Forms.Panel
    $toolbar.Dock = 'Top'; $toolbar.Height = 56; $toolbar.BackColor = $theme.Surface
    $form.Controls.Add($toolbar)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '  Recovery Toolkit'
    $title.ForeColor = $theme.Accent
    $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(12, 14)
    $toolbar.Controls.Add($title)

    $search = New-Object System.Windows.Forms.TextBox
    $search.Width = 260; $search.Location = New-Object System.Drawing.Point(320, 15)
    $search.BackColor = $theme.Surface2; $search.ForeColor = $theme.Text
    $search.BorderStyle = 'FixedSingle'
    $search.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $searchPlaceholder = 'Search tools and actions...'
    $search.Text = $searchPlaceholder; $search.ForeColor = $theme.TextMuted
    $toolbar.Controls.Add($search)

    $btnUpdateKit = New-RTFlatButton -Text 'Update Toolkit' -Width 130
    $btnUpdateKit.Location = New-Object System.Drawing.Point(610, 12)
    $toolbar.Controls.Add($btnUpdateKit)

    $btnUpdateTools = New-RTFlatButton -Text 'Update All Tools' -Width 140
    $btnUpdateTools.Location = New-Object System.Drawing.Point(748, 12)
    $toolbar.Controls.Add($btnUpdateTools)

    # --- Status bar (bottom) ----------------------------------------------
    $statusBar = New-Object System.Windows.Forms.Panel
    $statusBar.Dock = 'Bottom'; $statusBar.Height = 30; $statusBar.BackColor = $theme.Surface
    $form.Controls.Add($statusBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = 'Ready'; $statusLabel.ForeColor = $theme.TextMuted
    $statusLabel.AutoSize = $true; $statusLabel.Location = New-Object System.Drawing.Point(12, 7)
    $statusBar.Controls.Add($statusLabel)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Width = 220; $progress.Height = 14
    $progress.Style = 'Continuous'
    $progress.Location = New-Object System.Drawing.Point(0, 8)
    $progress.Anchor = 'Top,Right'
    $statusBar.Controls.Add($progress)
    $statusBar.Add_Resize({ $progress.Left = $statusBar.Width - $progress.Width - 12 })
    $progress.Left = $statusBar.Width - $progress.Width - 12

    # --- Log panel (bottom, above status) ---------------------------------
    $logBox = New-Object System.Windows.Forms.TextBox
    $logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'
    $logBox.Dock = 'Bottom'; $logBox.Height = 130
    $logBox.BackColor = [System.Drawing.Color]::FromArgb(12, 13, 17)
    $logBox.ForeColor = $theme.Success
    $logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $logBox.BorderStyle = 'FixedSingle'
    $form.Controls.Add($logBox)

    # --- Sidebar (left, category filter) ----------------------------------
    $sidebar = New-Object System.Windows.Forms.Panel
    $sidebar.Dock = 'Left'; $sidebar.Width = 190; $sidebar.BackColor = $theme.Surface
    $form.Controls.Add($sidebar)

    $catList = New-Object System.Windows.Forms.ListBox
    $catList.Dock = 'Fill'
    $catList.BackColor = $theme.Surface; $catList.ForeColor = $theme.Text
    $catList.BorderStyle = 'None'
    $catList.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $catList.ItemHeight = 30
    [void]$catList.Items.Add('All')
    foreach ($c in $Context.Categories) { [void]$catList.Items.Add($c) }
    $catList.SelectedIndex = 0
    $sidebar.Controls.Add($catList)

    $sideHeader = New-Object System.Windows.Forms.Label
    $sideHeader.Text = 'CATEGORIES'; $sideHeader.ForeColor = $theme.TextMuted
    $sideHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
    $sideHeader.Dock = 'Top'; $sideHeader.Height = 28; $sideHeader.TextAlign = 'MiddleLeft'
    $sideHeader.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
    $sidebar.Controls.Add($sideHeader)
    $sideHeader.BringToFront()

    # --- Content (center, action cards) -----------------------------------
    $content = New-Object System.Windows.Forms.FlowLayoutPanel
    $content.Dock = 'Fill'; $content.AutoScroll = $true
    $content.BackColor = $theme.Background
    $content.Padding = New-Object System.Windows.Forms.Padding(12)
    $form.Controls.Add($content)
    $content.BringToFront()

    # --- Action card factory ----------------------------------------------
    $makeCard = {
        param($action)
        $card = New-Object System.Windows.Forms.Panel
        $card.Width = 260; $card.Height = 92
        $card.Margin = New-Object System.Windows.Forms.Padding(8)
        $card.BackColor = $theme.Surface
        $card.Cursor = [System.Windows.Forms.Cursors]::Hand

        $name = New-Object System.Windows.Forms.Label
        $name.Text = $action.Name; $name.ForeColor = $theme.Text
        $name.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
        $name.Location = New-Object System.Drawing.Point(12, 10); $name.AutoSize = $true
        $name.MaximumSize = New-Object System.Drawing.Size(236, 0)
        $card.Controls.Add($name)

        $desc = New-Object System.Windows.Forms.Label
        $desc.Text = $action.Description; $desc.ForeColor = $theme.TextMuted
        $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $desc.Location = New-Object System.Drawing.Point(12, 36)
        $desc.MaximumSize = New-Object System.Drawing.Size(236, 44); $desc.AutoSize = $true
        $card.Controls.Add($desc)

        $cat = New-Object System.Windows.Forms.Label
        $cat.Text = $action.Category.ToUpper(); $cat.ForeColor = $theme.AccentDark
        $cat.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 7)
        $cat.Location = New-Object System.Drawing.Point(12, 72); $cat.AutoSize = $true
        $card.Controls.Add($cat)

        # Hover feedback. Capture colors as LOCALS first: GetNewClosure rebinds
        # $script: to a fresh module, so $script:RTTheme would resolve to $null
        # inside the closure and setting BackColor would throw.
        $hoverColor = $theme.Surface2
        $restColor  = $theme.Surface
        $enter = { $this.BackColor = $hoverColor }.GetNewClosure()
        $leave = { $this.BackColor = $restColor }.GetNewClosure()
        $card.Add_MouseEnter($enter); $card.Add_MouseLeave($leave)
        foreach ($child in $card.Controls) { $child.Add_MouseEnter($enter); $child.Add_MouseLeave($leave) }

        # Capture the runner locally for the same reason ($script: is rebound in
        # the closure). $script:RTRunAction is set before any card is created.
        $runner = $script:RTRunAction
        $click = {
            if ($sync.Running) {
                [System.Windows.Forms.MessageBox]::Show('An operation is already running. Please wait.', 'Busy') | Out-Null
                return
            }
            & $runner $action
        }.GetNewClosure()
        $card.Add_Click($click)
        foreach ($child in $card.Controls) { $child.Add_Click($click) }
        return $card
    }

    # --- Render / filter ---------------------------------------------------
    $renderCards = {
        $content.SuspendLayout()
        $content.Controls.Clear()
        $selectedCat = [string]$catList.SelectedItem
        $query = if ($search.Text -eq $searchPlaceholder) { '' } else { $search.Text.Trim() }
        foreach ($a in $Context.Actions) {
            if ($selectedCat -ne 'All' -and $a.Category -ne $selectedCat) { continue }
            if ($query -and ($a.Name -notmatch [regex]::Escape($query)) -and ($a.Description -notmatch [regex]::Escape($query))) { continue }
            $content.Controls.Add((& $makeCard $a))
        }
        if ($content.Controls.Count -eq 0) {
            $empty = New-Object System.Windows.Forms.Label
            $empty.Text = 'No matching actions.'; $empty.ForeColor = $theme.TextMuted
            $empty.AutoSize = $true; $empty.Margin = New-Object System.Windows.Forms.Padding(12)
            $content.Controls.Add($empty)
        }
        $content.ResumeLayout()
    }

    # --- Background action runner -----------------------------------------
    $script:RTRunAction = {
        param($action)
        $sync.Running = $true
        $sync.Progress = 0
        $sync.Status = "Running: $($action.Name)"
        $sync.LogQueue.Enqueue("=== $($action.Name) started ===")

        $ps = [powershell]::Create()
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
        $rs.SessionStateProxy.SetVariable('sync', $sync)
        $rs.SessionStateProxy.SetVariable('Context', $Context)
        $ps.Runspace = $rs

        [void]$ps.AddScript({
            param($actionScript, $context, $sync)
            # Global logging shim: modules imported by the action pick this up
            # (they only define a fallback when Write-RTLog is absent) so their
            # Write-RTLog output streams straight into the UI log queue.
            function global:Write-RTLog {
                param([string]$Message, [string]$Level = 'Info', [string]$Category = 'General')
                $sync.LogQueue.Enqueue("[$Level] $Message")
                if ($context.LogFile) {
                    $line = "{0} [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Category, $Message
                    Add-Content -Path $context.LogFile -Value $line -ErrorAction SilentlyContinue
                }
            }
            function Log([string]$m) { $sync.LogQueue.Enqueue($m) }
            function Set-RTProgress([int]$p) { $sync.Progress = $p }
            # Import every module into this fresh runspace AFTER Write-RTLog is
            # defined, so module logging streams to the UI. Actions can then call
            # any RT function directly without importing anything themselves.
            Get-ChildItem (Join-Path $context.Root 'Modules') -Filter *.psm1 |
                ForEach-Object { Import-Module $_.FullName -Force -DisableNameChecking -ErrorAction SilentlyContinue }
            try {
                & ([scriptblock]::Create($actionScript)) $context
                $sync.LogQueue.Enqueue('=== Completed ===')
            } catch {
                $sync.LogQueue.Enqueue("ERROR: $($_.Exception.Message)")
            } finally {
                $sync.Progress = 100
                $sync.Running = $false
                $sync.Status = 'Ready'
            }
        }).AddArgument($action.Script.ToString()).AddArgument($Context).AddArgument($sync)

        $handle = $ps.BeginInvoke()
        # Store for cleanup on close
        $script:RTActivePs = $ps; $script:RTActiveRs = $rs; $script:RTActiveHandle = $handle
    }.GetNewClosure()

    # --- UI refresh timer --------------------------------------------------
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 150
    $timer.Add_Tick({
        while ($sync.LogQueue.Count -gt 0) {
            $line = $sync.LogQueue.Dequeue()
            $logBox.AppendText(("[{0}] {1}{2}" -f (Get-Date -Format 'HH:mm:ss'), $line, [Environment]::NewLine))
        }
        $statusLabel.Text = $sync.Status
        $p = [int]$sync.Progress
        if ($p -ge 0 -and $p -le 100) { $progress.Value = $p }
        $statusLabel.ForeColor = if ($sync.Running) { $script:RTTheme.Warning } else { $script:RTTheme.TextMuted }
    })
    $timer.Start()

    # --- Wiring ------------------------------------------------------------
    $search.Add_Enter({ if ($search.Text -eq $searchPlaceholder) { $search.Text = ''; $search.ForeColor = $script:RTTheme.Text } })
    $search.Add_Leave({ if ([string]::IsNullOrWhiteSpace($search.Text)) { $search.Text = $searchPlaceholder; $search.ForeColor = $script:RTTheme.TextMuted } })
    $search.Add_TextChanged({ & $renderCards }.GetNewClosure())
    $catList.Add_SelectedIndexChanged({ & $renderCards }.GetNewClosure())

    $btnUpdateKit.Add_Click({
        if ($Context.OnUpdateToolkit) { & $Context.OnUpdateToolkit $sync }
    }.GetNewClosure())
    $btnUpdateTools.Add_Click({
        if ($Context.OnUpdateTools) { & $Context.OnUpdateTools $sync }
    }.GetNewClosure())

    $form.Add_FormClosing({
        $timer.Stop()
        try { if ($script:RTActivePs) { $script:RTActivePs.Dispose() } } catch {}
        try { if ($script:RTActiveRs) { $script:RTActiveRs.Dispose() } } catch {}
    })

    & $renderCards
    $logBox.AppendText("Recovery Toolkit ready. $($Context.Actions.Count) actions loaded.$([Environment]::NewLine)")

    if ($RenderPngPath) {
        # Off-screen capture for verification / documentation.
        $form.StartPosition = 'Manual'
        $form.Location = New-Object System.Drawing.Point(-4000, -4000)
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $dir = Split-Path $RenderPngPath -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($RenderPngPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $timer.Stop()
        $form.Close(); $form.Dispose()
        return
    }

    [void]$form.ShowDialog()
}

Export-ModuleMember -Function Show-RTMainWindow, New-RTFlatButton
