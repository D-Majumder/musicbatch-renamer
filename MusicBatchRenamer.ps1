# MusicBatch Renamer - Windows PowerShell 5.1+
# Safe, local-only music filename organizer. Audio contents are never read or modified.
# Launch GUI: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MusicBatchRenamer.ps1
# Preview-only CLI: .\MusicBatchRenamer.ps1 -Folder "C:\Music" -Preview
[CmdletBinding()]
param(
    [string]$Folder,
    [switch]$Preview,
    [switch]$NoGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SupportedExtensions = @('.mp3','.wav','.m4a','.aac','.flac','.ogg','.wma','.aiff','.aif','.opus')
$script:AppVersion = '1.0.0'

function Get-MusicPlan {
    param([Parameter(Mandatory)][string]$Path, [string]$PrefixPattern = '{0:D3}. {1}{2}', [switch]$Recursive)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Folder not found: $Path" }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $items = @(Get-ChildItem -LiteralPath $resolved -File -Recurse:$Recursive |
        Where-Object { $script:SupportedExtensions -contains $_.Extension.ToLowerInvariant() })
    if ($items.Count -eq 0) { return @() }

    $rows = foreach ($file in $items) {
        # Remove common existing numeric prefixes: "1. ", "001 - ", "02) ", "3_ "
        $title = $file.BaseName -replace '^\s*\d+\s*[.)_-]\s*', ''
        [PSCustomObject]@{
            SourcePath = $file.FullName
            Directory  = $file.DirectoryName
            OldName    = $file.Name
            Title      = $title.Trim()
            Extension  = $file.Extension
            SortKey    = $title.Trim()
            Length     = $file.Length
        }
    }
    $sorted = @($rows | Sort-Object -Property @{Expression={$_.SortKey}; Ascending=$true}, @{Expression={$_.OldName}; Ascending=$true})
    $plan = @()
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $row = $sorted[$i]
        $newName = [string]::Format([Globalization.CultureInfo]::InvariantCulture, $PrefixPattern, ($i + 1), $row.Title, $row.Extension)
        if ([string]::IsNullOrWhiteSpace($row.Title)) { throw "A filename has an empty title after removing its numeric prefix: $($row.OldName)" }
        if ($newName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { throw "Generated filename contains invalid characters: $newName" }
        $plan += [PSCustomObject]@{
            Number = $i + 1
            OldName = $row.OldName
            NewName = $newName
            SourcePath = $row.SourcePath
            TargetPath = Join-Path $row.Directory $newName
            Directory = $row.Directory
            Title = $row.Title
            Extension = $row.Extension
            Length = $row.Length
        }
    }

    # Windows paths are case-insensitive. Do not allow duplicate destinations.
    $destKeys = @{}
    foreach ($p in $plan) {
        $key = $p.TargetPath.ToLowerInvariant()
        if ($destKeys.ContainsKey($key)) { throw "Two songs would have the same destination filename: $($p.NewName)" }
        $destKeys[$key] = $true
    }
    $sourceKeys = @{}
    foreach ($p in $plan) { $sourceKeys[$p.SourcePath.ToLowerInvariant()] = $true }
    foreach ($p in $plan) {
        if (Test-Path -LiteralPath $p.TargetPath) {
            $targetKey = $p.TargetPath.ToLowerInvariant()
            $sourceKey = $p.SourcePath.ToLowerInvariant()
            if (-not $sourceKeys.ContainsKey($targetKey)) {
                throw "Destination already exists and is not being renamed: $($p.TargetPath)"
            }
        }
    }
    return ,$plan
}

function Invoke-MusicRename {
    param([Parameter(Mandatory)][object[]]$Plan, [Parameter(Mandatory)][string]$RootFolder)
    if ($Plan.Count -eq 0) { throw 'No supported audio files found.' }

    $changes = @($Plan | Where-Object { $_.OldName -cne $_.NewName })
    if ($changes.Count -eq 0) { return [PSCustomObject]@{ Count = 0; Manifest = $null; Message = 'All filenames already match the plan.' } }

    # Verify sources and destinations immediately before touching anything.
    foreach ($p in $changes) {
        if (-not (Test-Path -LiteralPath $p.SourcePath -PathType Leaf)) { throw "Source file disappeared: $($p.SourcePath)" }
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $manifest = Join-Path $RootFolder "MusicBatchRenamer-undo-$stamp.csv"
    $manifestRows = @($changes | ForEach-Object {
        [PSCustomObject]@{ OldPath = $_.SourcePath; NewPath = $_.TargetPath; OldName = $_.OldName; NewName = $_.NewName }
    })
    $manifestRows | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding UTF8

    $staged = New-Object System.Collections.Generic.List[object]
    try {
        # Phase 1: move every changed file to a unique temporary name in the same directory.
        foreach ($p in $changes) {
            $tempName = '.mbr-tmp-' + [guid]::NewGuid().ToString('N') + $p.Extension
            $tempPath = Join-Path $p.Directory $tempName
            Rename-Item -LiteralPath $p.SourcePath -NewName $tempName
            $staged.Add([PSCustomObject]@{ TempPath = $tempPath; OldPath = $p.SourcePath; NewPath = $p.TargetPath; OldName = $p.OldName; NewName = $p.NewName; State = 'Staged' })
        }
        # Phase 2: move temporary files to their destinations.
        foreach ($s in $staged) {
            Rename-Item -LiteralPath $s.TempPath -NewName $s.NewName
            $s.State = 'Final'
        }
        return [PSCustomObject]@{ Count = $changes.Count; Manifest = $manifest; Message = "Renamed $($changes.Count) files successfully." }
    } catch {
        $failure = $_.Exception.Message
        # Best-effort rollback: first put any completed destinations back to unique temporary names.
        foreach ($s in $staged) {
            $finalPath = Join-Path (Split-Path -Parent $s.OldPath) $s.NewName
            if (Test-Path -LiteralPath $finalPath) {
                try {
                    $rollbackName = '.mbr-rollback-' + [guid]::NewGuid().ToString('N') + [IO.Path]::GetExtension($finalPath)
                    Rename-Item -LiteralPath $finalPath -NewName $rollbackName
                    $s.TempPath = Join-Path (Split-Path -Parent $finalPath) $rollbackName
                } catch { }
            }
        }
        foreach ($s in $staged) {
            if (Test-Path -LiteralPath $s.TempPath) {
                try { Rename-Item -LiteralPath $s.TempPath -NewName $s.OldName } catch { }
            }
        }
        throw "Rename failed: $failure. A rollback was attempted. Check the folder and undo CSV: $manifest"
    }
}

function Undo-MusicRename {
    param([Parameter(Mandatory)][string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
    $rows = @(Import-Csv -LiteralPath $ManifestPath)
    if ($rows.Count -eq 0) { throw 'Manifest is empty.' }
    foreach ($r in $rows) {
        if (-not (Test-Path -LiteralPath $r.NewPath -PathType Leaf)) { throw "Cannot undo: renamed file is missing: $($r.NewPath)" }
        if (Test-Path -LiteralPath $r.OldPath) { throw "Cannot undo: original path is occupied: $($r.OldPath)" }
    }
    $staged = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($r in $rows) {
            $ext = [IO.Path]::GetExtension($r.NewPath)
            $tempName = '.mbr-undo-' + [guid]::NewGuid().ToString('N') + $ext
            $tempPath = Join-Path (Split-Path -Parent $r.NewPath) $tempName
            Rename-Item -LiteralPath $r.NewPath -NewName $tempName
            $staged.Add([PSCustomObject]@{ TempPath = $tempPath; OldPath = $r.OldPath; OldName = $r.OldName })
        }
        foreach ($s in $staged) { Rename-Item -LiteralPath $s.TempPath -NewName $s.OldName }
        return "Undo complete. Restored $($rows.Count) filenames."
    } catch {
        throw "Undo was interrupted: $($_.Exception.Message). Some files may need manual recovery."
    }
}

function Start-MusicBatchGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MusicBatch Renamer $script:AppVersion"
    $form.Size = New-Object System.Drawing.Size(1000, 690)
    $form.MinimumSize = New-Object System.Drawing.Size(820, 540)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $folderLabel = New-Object System.Windows.Forms.Label
    $folderLabel.Text = 'Music folder'
    $folderLabel.Location = New-Object System.Drawing.Point(16, 18)
    $folderLabel.AutoSize = $true
    $form.Controls.Add($folderLabel)

    $folderBox = New-Object System.Windows.Forms.TextBox
    $folderBox.Location = New-Object System.Drawing.Point(16, 42)
    $folderBox.Size = New-Object System.Drawing.Size(760, 28)
    $folderBox.Anchor = 'Top,Left,Right'
    if ($Folder) { $folderBox.Text = $Folder }
    $form.Controls.Add($folderBox)

    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Browse...'
    $browse.Location = New-Object System.Drawing.Point(790, 40)
    $browse.Size = New-Object System.Drawing.Size(175, 30)
    $browse.Anchor = 'Top,Right'
    $form.Controls.Add($browse)

    $prefixLabel = New-Object System.Windows.Forms.Label
    $prefixLabel.Text = 'Filename format: {0} = number, {1} = title, {2} = extension'
    $prefixLabel.Location = New-Object System.Drawing.Point(16, 82)
    $prefixLabel.AutoSize = $true
    $form.Controls.Add($prefixLabel)

    $prefixBox = New-Object System.Windows.Forms.TextBox
    $prefixBox.Text = '{0:D3}. {1}{2}'
    $prefixBox.Location = New-Object System.Drawing.Point(16, 105)
    $prefixBox.Size = New-Object System.Drawing.Size(360, 26)
    $form.Controls.Add($prefixBox)

    $recursiveBox = New-Object System.Windows.Forms.CheckBox
    $recursiveBox.Text = 'Include subfolders (each folder gets its own sequence)'
    $recursiveBox.Location = New-Object System.Drawing.Point(400, 106)
    $recursiveBox.AutoSize = $true
    $recursiveBox.Enabled = $false # Intentionally disabled until nested-folder transaction support is fully implemented.
    $form.Controls.Add($recursiveBox)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(16, 145)
    $grid.Size = New-Object System.Drawing.Size(949, 410)
    $grid.Anchor = 'Top,Bottom,Left,Right'
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AutoSizeColumnsMode = 'Fill'
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $false
    $grid.RowHeadersVisible = $false
    $form.Controls.Add($grid)

    $status = New-Object System.Windows.Forms.Label
    $status.Text = 'Choose a folder, then click Preview. No files change during preview.'
    $status.Location = New-Object System.Drawing.Point(16, 565)
    $status.Size = New-Object System.Drawing.Size(949, 24)
    $status.Anchor = 'Bottom,Left,Right'
    $form.Controls.Add($status)

    $previewBtn = New-Object System.Windows.Forms.Button
    $previewBtn.Text = 'Preview'
    $previewBtn.Location = New-Object System.Drawing.Point(16, 600)
    $previewBtn.Size = New-Object System.Drawing.Size(130, 34)
    $previewBtn.Anchor = 'Bottom,Left'
    $form.Controls.Add($previewBtn)

    $renameBtn = New-Object System.Windows.Forms.Button
    $renameBtn.Text = 'Rename files'
    $renameBtn.Location = New-Object System.Drawing.Point(156, 600)
    $renameBtn.Size = New-Object System.Drawing.Size(150, 34)
    $renameBtn.Anchor = 'Bottom,Left'
    $renameBtn.Enabled = $false
    $form.Controls.Add($renameBtn)

    $undoBtn = New-Object System.Windows.Forms.Button
    $undoBtn.Text = 'Undo from CSV...'
    $undoBtn.Location = New-Object System.Drawing.Point(316, 600)
    $undoBtn.Size = New-Object System.Drawing.Size(150, 34)
    $undoBtn.Anchor = 'Bottom,Left'
    $form.Controls.Add($undoBtn)

    $openBtn = New-Object System.Windows.Forms.Button
    $openBtn.Text = 'Open folder'
    $openBtn.Location = New-Object System.Drawing.Point(476, 600)
    $openBtn.Size = New-Object System.Drawing.Size(130, 34)
    $openBtn.Anchor = 'Bottom,Left'
    $form.Controls.Add($openBtn)

    $script:CurrentPlan = @()
    $browse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the folder containing your music files'
        if (Test-Path -LiteralPath $folderBox.Text -PathType Container) { $dialog.SelectedPath = $folderBox.Text }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderBox.Text = $dialog.SelectedPath
            $renameBtn.Enabled = $false
            $grid.DataSource = $null
            $script:CurrentPlan = @()
        }
        $dialog.Dispose()
    })
    $previewBtn.Add_Click({
        try {
            $script:CurrentPlan = @(Get-MusicPlan -Path $folderBox.Text -PrefixPattern $prefixBox.Text)
            $view = @($script:CurrentPlan | Select-Object Number, OldName, NewName, @{N='Size (KB)';E={[math]::Round($_.Length / 1KB, 1)}})
            $grid.DataSource = $null
            $grid.DataSource = $view
            $changed = @($script:CurrentPlan | Where-Object { $_.OldName -cne $_.NewName }).Count
            $status.Text = "Found $($script:CurrentPlan.Count) audio files; $changed filename(s) would change. Audio contents are not modified."
            $renameBtn.Enabled = ($changed -gt 0)
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Preview error', 'OK', 'Error') | Out-Null
            $status.Text = 'Preview failed. No files changed.'
            $renameBtn.Enabled = $false
        }
    })
    $renameBtn.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Rename the previewed files in:`r`n$($folderBox.Text)`r`n`r`nThis changes filenames only. A CSV undo map will be saved. Continue?",
            'Confirm rename', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        try {
            # Rebuild plan immediately before rename to catch folder changes since preview.
            $freshPlan = @(Get-MusicPlan -Path $folderBox.Text -PrefixPattern $prefixBox.Text)
            $result = Invoke-MusicRename -Plan $freshPlan -RootFolder (Resolve-Path -LiteralPath $folderBox.Text).Path
            [System.Windows.Forms.MessageBox]::Show("$($result.Message)`r`nUndo map: $($result.Manifest)", 'Complete', 'OK', 'Information') | Out-Null
            $previewBtn.PerformClick()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Rename error', 'OK', 'Error') | Out-Null
        }
    })
    $undoBtn.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select a MusicBatch Renamer undo CSV'
        $dialog.Filter = 'Undo manifest (*.csv)|MusicBatchRenamer-undo-*.csv|CSV files (*.csv)|*.csv'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $answer = [System.Windows.Forms.MessageBox]::Show("Restore original filenames using this manifest?`r`n$($dialog.FileName)", 'Confirm undo', 'YesNo', 'Warning')
            if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    $msg = Undo-MusicRename -ManifestPath $dialog.FileName
                    [System.Windows.Forms.MessageBox]::Show($msg, 'Undo complete', 'OK', 'Information') | Out-Null
                    $previewBtn.PerformClick()
                } catch {
                    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Undo error', 'OK', 'Error') | Out-Null
                }
            }
        }
        $dialog.Dispose()
    })
    $openBtn.Add_Click({
        if (Test-Path -LiteralPath $folderBox.Text -PathType Container) {
            Start-Process explorer.exe -ArgumentList @($folderBox.Text)
        } else {
            [System.Windows.Forms.MessageBox]::Show('Choose a valid folder first.', 'Folder missing', 'OK', 'Warning') | Out-Null
        }
    })
    [void]$form.ShowDialog()
    $form.Dispose()
}

if ($Preview) {
    if (-not $Folder) { throw 'Use -Folder "C:\Path\To\Music" with -Preview.' }
    $plan = @(Get-MusicPlan -Path $Folder)
    $plan | Select-Object Number, OldName, NewName, @{N='Size (KB)';E={[math]::Round($_.Length / 1KB, 1)}} | Format-Table -AutoSize
    Write-Host "Preview only. No files changed."
} elseif ($NoGui) {
    if (-not $Folder) { throw 'Use -Folder "C:\Path\To\Music" with -NoGui.' }
    $plan = @(Get-MusicPlan -Path $Folder)
    $plan | Select-Object Number, OldName, NewName | Format-Table -AutoSize
    $confirm = Read-Host 'Type RENAME to apply, or anything else to cancel'
    if ($confirm -ceq 'RENAME') {
        $result = Invoke-MusicRename -Plan $plan -RootFolder (Resolve-Path -LiteralPath $Folder).Path
        Write-Host $result.Message
        if ($result.Manifest) { Write-Host "Undo map: $($result.Manifest)" }
    } else { Write-Host 'Cancelled. No files changed.' }
} else {
    Start-MusicBatchGui
}
