<# :
@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content '%~f0') -join \"`n\")"
exit /b
#>

# ==============================================================================
#  PORTABLE USER ENVIRONMENT MANAGER (PortaPath) BY https://github.com/MohaKalaf 
# ==============================================================================

# -- UI INJECTION --
$cSharpCode = @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Win32
{
    public class HD
    {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
        public static void SetHighDPI()
        {
            try { SetProcessDpiAwareness(1); } catch {}
            try { SetProcessDPIAware(); } catch {}
        }
    }
    public class FolderPicker
    {
        public static string ShowDialog(string initialDirectory, string title)
        {
            var dialog = new OpenFileDialog();
            dialog.ValidateNames = false;
            dialog.CheckFileExists = false;
            dialog.CheckPathExists = true;
            dialog.FileName = "Select Folder";
            dialog.Filter = "Folders|no.files";
            dialog.Title = title;
            if (!string.IsNullOrEmpty(initialDirectory)) { dialog.InitialDirectory = initialDirectory; }
            if (dialog.ShowDialog() == DialogResult.OK) {
                return System.IO.Path.GetDirectoryName(dialog.FileName);
            }
            return "";
        }
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'Win32.HD').Type) {
    Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies System.Windows.Forms
}
[Win32.HD]::SetHighDPI()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


# -- HELPER FUNCTIONS --
# Helper to force REG_EXPAND_SZ if value contains % variables
function Set-RegistryEnv($name, $value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
    if ($value -match "%") {
        $key.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } else {
        $key.SetValue($name, $value, [Microsoft.Win32.RegistryValueKind]::String)
    }
    $key.Close()
}

# --- CONSTANTS ---
$script:scriptPath = (Get-Location).Path
$script:driveRoot = (Get-PSDrive -Name (Get-Location).Drive.Name).Root.TrimEnd('\')
$configFile = "$script:scriptPath\portapath_config.json"


# -- PLACEHOLDERS --
$phName = "(Name)"
$phPath = "(Select Folder Path)"
$phVar  = "(ENV_VAR)"


# -- CONFIG LOGIC --
function Get-DefaultConfig { return @() }

function Load-Config {
    if (Test-Path $configFile) {
        try { 
            $raw = Get-Content $configFile -Raw | ConvertFrom-Json 
            # Self-Healing: Filter out nulls
            return @($raw) | Where-Object { $_ -ne $null -and $_.Label }
        } 
        catch { return Get-DefaultConfig }
    }
    return Get-DefaultConfig
}

function Save-Config {
    $grid.EndEdit()
    $list = @()
    foreach ($row in $grid.Rows) {
        if (-not $row.IsNewRow) {
            $n = $row.Cells[0].Value
            $p = $row.Cells[1].Value
            $v = $row.Cells[2].Value
        
            $validName = (-not [string]::IsNullOrWhiteSpace($n)) -and ($n -ne $phName)
            $validPath = (-not [string]::IsNullOrWhiteSpace($p)) -and ($p -ne $phPath)
            
            if ($validName -or $validPath) {
                 if ($n -eq $phName) { $n = "" }
                 if ($p -eq $phPath) { $p = "" }
                 if ($v -eq $phVar)  { $v = "" }
                 $list += @{ Label = $n; Path = $p; EnvVar = $v }
            }
        }
    }
    
    if ($list.Count -eq 0) {
        Set-Content -Path $configFile -Value "[]" -Encoding UTF8
    } else {
        $json = ConvertTo-Json -InputObject @($list) -Depth 10
        Set-Content -Path $configFile -Value $json -Encoding UTF8
    }
}


# -- GUI SETUP --
$form = New-Object System.Windows.Forms.Form
$form.Text = "PortaPath"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.Font = [System.Drawing.SystemFonts]::MessageBoxFont 


# -- STATUS COMPONENT --
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(20, 20)
$lblStatus.Size = New-Object System.Drawing.Size(720, 40)
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblStatus.TextAlign = "MiddleCenter"
$lblStatus.Anchor = "Top, Left, Right"
$form.Controls.Add($lblStatus)


# -- ENTRIES GRID --
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(30, 80)
$grid.Size = New-Object System.Drawing.Size(720, 300) 
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = "FullRowSelect"
$grid.MultiSelect = $false
$grid.BackgroundColor = "White"
$grid.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$grid.RowTemplate.Height = 35 
$grid.ColumnHeadersHeight = 35
$grid.AutoSizeColumnsMode = "Fill"
$grid.Anchor = "Top, Bottom, Left, Right"
$grid.BorderStyle = "Fixed3D"
$grid.EditMode = "EditOnEnter"


# -- COLUMNS --
$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = "Label"
$colName.FillWeight = 20
$grid.Columns.Add($colName) | Out-Null

$colPath = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPath.HeaderText = "Folder Path"
$colPath.FillWeight = 40
$grid.Columns.Add($colPath) | Out-Null

$colVar = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colVar.HeaderText = "Env Var (Optional)"
$colVar.FillWeight = 25
$grid.Columns.Add($colVar) | Out-Null

$colBtn = New-Object System.Windows.Forms.DataGridViewButtonColumn
$colBtn.HeaderText = "Browse"
$colBtn.FillWeight = 15
$colBtn.Text = "..."
$colBtn.UseColumnTextForButtonValue = $true
$grid.Columns.Add($colBtn) | Out-Null

$form.Controls.Add($grid)


# -- EMPTY STATE COMPONENT --
$lblEmpty = New-Object System.Windows.Forms.Label
$lblEmpty.Text = "There are currently no entries.`n`nClick the '+' button to add a new one."
$lblEmpty.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
$lblEmpty.ForeColor = "Gray"
$lblEmpty.TextAlign = "MiddleCenter"
$lblEmpty.BackColor = "White"
$lblEmpty.Location = New-Object System.Drawing.Point(32, 116) 
$lblEmpty.Size = New-Object System.Drawing.Size(716, 262)
$lblEmpty.Anchor = "Top, Bottom, Left, Right"
$form.Controls.Add($lblEmpty)
$lblEmpty.BringToFront()


# -- BUTTON COMPONENTS --
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "+"
$btnAdd.Size = New-Object System.Drawing.Size(45, 40)
$btnAdd.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$btnAdd.Anchor = "Bottom, Left"
$form.Controls.Add($btnAdd)

$btnRem = New-Object System.Windows.Forms.Button
$btnRem.Text = "-"
$btnRem.Size = New-Object System.Drawing.Size(45, 40)
$btnRem.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$btnRem.Anchor = "Bottom, Left"
$form.Controls.Add($btnRem)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save"
$btnSave.Size = New-Object System.Drawing.Size(100, 40)
$btnSave.Font = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
$btnSave.Anchor = "Bottom, Left"
$form.Controls.Add($btnSave)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Hint: 'Env Var' sets a HOME variable. The path is ALWAYS added to PATH."
$lblHint.Size = New-Object System.Drawing.Size(630, 30)
$lblHint.ForeColor = "Gray"
$lblHint.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblHint.Anchor = "Bottom, Left, Right"
$form.Controls.Add($lblHint)

$btnActivate = New-Object System.Windows.Forms.Button
$btnActivate.Text = "ACTIVATE"
$btnActivate.Size = New-Object System.Drawing.Size(200, 60)
$btnActivate.BackColor = [System.Drawing.Color]::LightGreen
$btnActivate.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnActivate.Anchor = "Bottom"
$form.Controls.Add($btnActivate)

$btnDeactivate = New-Object System.Windows.Forms.Button
$btnDeactivate.Text = "DEACTIVATE"
$btnDeactivate.Size = New-Object System.Drawing.Size(200, 60)
$btnDeactivate.BackColor = [System.Drawing.Color]::LightCoral
$btnDeactivate.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnDeactivate.Anchor = "Bottom"
$form.Controls.Add($btnDeactivate)


# -- CHECKS --
function Check-EmptyState {
    if ($grid.Rows.Count -eq 0) {
        $lblEmpty.Visible = $true
    } else {
        $lblEmpty.Visible = $false
    }
}


# -- GRID CELL FORMATTING --
$grid.Add_CellFormatting({
    param($sender, $e)
    $val = $e.Value
    if ($val -eq $phName -or $val -eq $phPath -or $val -eq $phVar) {
        $e.CellStyle.ForeColor = [System.Drawing.Color]::Gray
        $e.CellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
    } else {
        $e.CellStyle.ForeColor = [System.Drawing.Color]::Black
        $e.CellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    }
})

$grid.Add_CellBeginEdit({
    param($sender, $e)
    $row = $grid.Rows[$e.RowIndex]
    $cell = $row.Cells[$e.ColumnIndex]
    if ($e.ColumnIndex -eq 0 -and $cell.Value -eq $phName) { $cell.Value = "" }
    if ($e.ColumnIndex -eq 1 -and $cell.Value -eq $phPath) { $cell.Value = "" }
    if ($e.ColumnIndex -eq 2 -and $cell.Value -eq $phVar)  { $cell.Value = "" }
})

$grid.Add_CellEndEdit({
    param($sender, $e)
    $row = $grid.Rows[$e.RowIndex]
    $cell = $row.Cells[$e.ColumnIndex]
    if ($e.ColumnIndex -eq 0 -and [string]::IsNullOrWhiteSpace($cell.Value)) { $cell.Value = $phName }
    if ($e.ColumnIndex -eq 1 -and [string]::IsNullOrWhiteSpace($cell.Value)) { $cell.Value = $phPath }
    if ($e.ColumnIndex -eq 2 -and [string]::IsNullOrWhiteSpace($cell.Value)) { $cell.Value = $phVar }
})


# -- BUTTON CLICK LISTENERS --
$btnAdd.Add_Click({ 
    [void]$grid.Rows.Add($phName, $phPath, $phVar)
    Check-EmptyState
})

$btnRem.Add_Click({ 
    if ($grid.SelectedRows.Count -gt 0) { 
        [void]$grid.Rows.Remove($grid.SelectedRows[0])
    }
    Check-EmptyState
})

$btnSave.Add_Click({
    Save-Config
    [System.Windows.Forms.MessageBox]::Show("Config saved to portapath_config.json", "Success")
    Check-EmptyState
})

$grid.Add_CellContentClick({ 
    param($sender, $e)
    if ($e.ColumnIndex -eq 3 -and $e.RowIndex -ge 0) {
        $current = $grid.Rows[$e.RowIndex].Cells[1].Value
        $startDir = $script:scriptPath
        if (-not [string]::IsNullOrWhiteSpace($current) -and $current -ne $phPath) {
            $check = "$script:driveRoot\$current"
            if (Test-Path $check) { $startDir = $check }
        }
        $sel = [Win32.FolderPicker]::ShowDialog($startDir, "Select Folder")
        if (-not [string]::IsNullOrWhiteSpace($sel)) {
            if (-not [string]::IsNullOrEmpty($script:scriptPath) -and $sel.StartsWith($script:scriptPath)) {
                $sel = $sel.Replace($script:scriptPath, "").TrimStart('\')
            }
            $grid.Rows[$e.RowIndex].Cells[1].Value = $sel
        }
    }
})


# -- WINDOW LAYOUT LOGIC --
function Update-Layout {
    $h = $form.ClientSize.Height
    $w = $form.ClientSize.Width
    $center = $w / 2
    $btnY = $h - 80
    $btnActivate.Location = New-Object System.Drawing.Point(($center - 210), $btnY)
    $btnDeactivate.Location = New-Object System.Drawing.Point(($center + 10), $btnY)
    $smallBtnY = $h - 140
    $btnAdd.Location = New-Object System.Drawing.Point(30, $smallBtnY)
    $btnRem.Location = New-Object System.Drawing.Point(85, $smallBtnY)
    $btnSave.Location = New-Object System.Drawing.Point(30, ($smallBtnY + 50))
    $lblHint.Location = New-Object System.Drawing.Point(150, ($smallBtnY + 10))
    
    $gridHeight = $smallBtnY - 100
    if ($gridHeight -lt 100) { $gridHeight = 100 }
    $grid.Height = $gridHeight
    $lblEmpty.Location = New-Object System.Drawing.Point(32, 116)
    $lblEmpty.Size = New-Object System.Drawing.Size(($w - 84), ($gridHeight - 38))
}
[void]$form.Add_Resize({ Update-Layout })

function Resolve-PathInput($inputPath) {
    if ([string]::IsNullOrWhiteSpace($inputPath)) { return "" }
    if ($inputPath -eq $phPath) { return "" }
    
    # If it starts with %, return it exactly as-is (Raw Mode)
    if ($inputPath.StartsWith("%")) { return $inputPath }
    
    if ($inputPath -match "^[a-zA-Z]:") { return $inputPath }
    return "$script:driveRoot\$inputPath"
}

function Update-Status {
    $User = [EnvironmentVariableTarget]::User
    $marker = [Environment]::GetEnvironmentVariable('PORTAPATH_ACTIVE', $User)
    if ($marker -eq "1") {
        $lblStatus.Text = "STATUS: ACTIVE (Injected)"
        $lblStatus.ForeColor = "Green"
        $btnActivate.Enabled = $false; $btnDeactivate.Enabled = $true
    } else {
        $lblStatus.Text = "STATUS: INACTIVE (Clean)"
        $lblStatus.ForeColor = "Red"
        $btnActivate.Enabled = $true; $btnDeactivate.Enabled = $false
    }
}


# -- TOGGLE BUTTONS LOGIC --
$btnActivate.Add_Click({
    Save-Config
    $User = [EnvironmentVariableTarget]::User
    $CurrentPath = [Environment]::GetEnvironmentVariable('Path', $User)
    $CurrentPathParts = $CurrentPath -split ";" | Where-Object { $_.Trim() -ne "" }
    $NewPathEntries = @()
    $IsModified = $false

    foreach ($row in $grid.Rows) {
        if (-not $row.IsNewRow) {
            $rawPath = $row.Cells[1].Value
            $envVar  = $row.Cells[2].Value
            $fullPath = Resolve-PathInput $rawPath
            
            if ($fullPath -ne "" -and $rawPath -ne $phPath) {
                
                # Smart Env Var
                if (-not [string]::IsNullOrWhiteSpace($envVar) -and $envVar -ne $phVar) {
                    $existing = [Environment]::GetEnvironmentVariable($envVar, $User)
                    if ($existing -ne $fullPath) {
                        # Use Registry helper to support %Variables%
                        Set-RegistryEnv $envVar $fullPath
                    }
                }
                
                # Pure Path
                $targetPath = $fullPath
                
                if ($CurrentPathParts -notcontains $targetPath) {
                    $NewPathEntries += $targetPath
                    $IsModified = $true
                }
            }
        }
    }
    
    if ($IsModified) {
        $NewPathString = ($NewPathEntries -join ";") + ";" + $CurrentPath
        # FIX: Use Registry helper for PATH to ensure expansion works
        Set-RegistryEnv 'Path' $NewPathString
        
        # Trigger Broadcast
        [Environment]::SetEnvironmentVariable('PORTAPATH_ACTIVE', "1", $User)
    } else {
        [Environment]::SetEnvironmentVariable('PORTAPATH_ACTIVE', "1", $User)
    }
    
    [System.Windows.Forms.MessageBox]::Show("Activated!", "Success")
    Update-Status
})

$btnDeactivate.Add_Click({
    $User = [EnvironmentVariableTarget]::User
    $CurrentPath = [Environment]::GetEnvironmentVariable('Path', $User)
    
    # 1. PREPARE PATH LIST
    [System.Collections.Generic.List[string]]$PathList = $CurrentPath -split ";" | Where-Object { $_.Trim() -ne "" }

    # 2. SURGICAL REMOVAL (Known Grid Items)
    foreach ($row in $grid.Rows) {
        if (-not $row.IsNewRow) {
            $rawPath = $row.Cells[1].Value
            $envVar  = $row.Cells[2].Value
            $fullPath = Resolve-PathInput $rawPath

            if ($fullPath -ne "") {
                # Remove ENV
                if (-not [string]::IsNullOrWhiteSpace($envVar) -and $envVar -ne $phVar) {
                    if ([Environment]::GetEnvironmentVariable($envVar, $User) -ne $null) {
                        [Environment]::SetEnvironmentVariable($envVar, $null, $User)
                    }
                }
                # Remove PATH
                $targetBin = "$fullPath\bin"
                $targetRoot = $fullPath
                if ($PathList.Contains($targetBin)) { [void]$PathList.Remove($targetBin) }
                if ($PathList.Contains($targetRoot)) { [void]$PathList.Remove($targetRoot) }
            }
        }
    }

    # 3. ORPHAN CHECK (Interactive)
    $Orphans = @()
    foreach ($p in $PathList) {
        # Identify paths belonging to THIS drive that are still lingering
        if ($p.StartsWith($script:driveRoot)) {
            $Orphans += $p
        }
    }

    if ($Orphans.Count -gt 0) {
        $msg = "Found $($Orphans.Count) path(s) on this drive that are NOT in your config:`n`n"
        $limit = 0
        foreach ($o in $Orphans) {
            if ($limit -lt 10) { $msg += "$o`n" }
            $limit++
        }
        if ($Orphans.Count -gt 10) { $msg += "...and $($Orphans.Count - 10) more.`n" }
        $msg += "`nThese might be old tools you removed from the list.`nDo you want to remove them?"

        $result = [System.Windows.Forms.MessageBox]::Show($msg, "Orphaned Paths Detected", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            foreach ($o in $Orphans) {
                [void]$PathList.Remove($o)
            }
        }
    }

    # 4. COMMIT
    $NewPath = $PathList -join ";"
    [Environment]::SetEnvironmentVariable('Path', $NewPath, $User)
    [Environment]::SetEnvironmentVariable('PORTAPATH_ACTIVE', $null, $User)

    [System.Windows.Forms.MessageBox]::Show("Deactivated.", "Success")
    Update-Status
})


# -- PROGRAM STARTING POINT --
$initialData = Load-Config
if ($initialData.Count -eq 0) {
    # No Default Row added, rely on Empty State Label
} else {
    foreach ($item in $initialData) {
        $n = if ($item.Label) { $item.Label } else { $phName }
        $p = if ($item.Path)  { $item.Path }  else { $phPath }
        $v = if ($item.EnvVar){ $item.EnvVar } else { $phVar }
        [void]$grid.Rows.Add($n, $p, $v) 
    }
}

Check-EmptyState
Update-Layout
Update-Status

$grid.ClearSelection()

try { $form.ShowDialog() } catch {}

