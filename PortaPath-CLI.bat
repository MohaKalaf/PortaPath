<# :
@echo off
setlocal
cd /d "%~dp0"
set "PORTAPATH_SCRIPT=%~f0"
:: HEADER: Using @args to correctly splat arguments.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Get-Content -LiteralPath $env:PORTAPATH_SCRIPT -Raw))) @args" %*
exit /b
#>

# ==============================================================================
#  PORTAPATH CLI (Interactive Safety Edition)
# ==============================================================================

# 1. SETUP & CONFIGURATION
$scriptPath = (Get-Location).Path
$driveRoot = (Get-PSDrive -Name (Get-Location).Drive.Name).Root.TrimEnd('\')
$configFile = "$scriptPath\portapath_config.json"

function Get-Config {
    if (Test-Path $configFile) {
        try { 
            $raw = Get-Content $configFile -Raw | ConvertFrom-Json 
            return @($raw) | Where-Object { $_ -ne $null -and $_.Label }
        } catch { 
            return @() 
        }
    }
    return @()
}

function Save-Config ($data) {
    if (-not $data -or $data.Count -eq 0) {
        Set-Content -Path $configFile -Value "[]" -Encoding UTF8
    } else {
        $json = ConvertTo-Json -InputObject @($data) -Depth 10
        Set-Content -Path $configFile -Value $json -Encoding UTF8
    }
}

function Resolve-PathInput($inputPath) {
    if ([string]::IsNullOrWhiteSpace($inputPath)) { return "" }
    # FIX: If it starts with %, return it exactly as-is
    if ($inputPath.StartsWith("%")) { return $inputPath }
    if ($inputPath -match "^[a-zA-Z]:") { return $inputPath }
    return "$driveRoot\$inputPath"
}

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

# 2. ACTIONS

function Action-List {
    if (-not (Test-Path $configFile)) {
        Write-Warning "Config file not found."
        Write-Host "Generating new empty config at: $configFile" -ForegroundColor Yellow
        Set-Content -Path $configFile -Value "[]" -Encoding UTF8
        $data = @()
    } else {
        Write-Host "Config file found at: $configFile" -ForegroundColor Gray
        $data = Get-Config
    }

    if ($data.Count -eq 0) {
        Write-Warning "The list is empty."
    } else {
        Write-Host "Current PortaPath Configuration:" -ForegroundColor Cyan
        Write-Host "--------------------------------" -ForegroundColor DarkGray
        $data | Format-Table -Property Label, Path, EnvVar -AutoSize
    }
}

function Action-Add ($label, $path, $envVar) {
    $data = @(Get-Config)
    
    if ([string]::IsNullOrWhiteSpace($label) -or [string]::IsNullOrWhiteSpace($path)) {
        Write-Error "Usage: PortaPath-CLI.bat add <Label> <Path> [EnvVar]"
        return
    }

    $newItem = @{
        Label  = $label
        Path   = $path
        EnvVar = if ($envVar) { $envVar } else { "" }
    }
    
    $data += $newItem
    Save-Config $data
    Write-Host "Added '$label' -> '$path'" -ForegroundColor Cyan
}

function Action-Remove ($label) {
    $data = @(Get-Config)
    
    $newData = @($data | Where-Object { $_.Label -ne $label })
    
    if ($data.Count -eq $newData.Count) {
        Write-Warning "No entry found with label '$label'"
    } else {
        Save-Config $newData
        Write-Host "Removed '$label'" -ForegroundColor Yellow
    }
}

function Action-Activate {
    $config = Get-Config
    if ($config.Count -eq 0) {
        Write-Warning "Configuration is empty. Add entries before activating."
        return
    }

    $User = [EnvironmentVariableTarget]::User
    $CurrentPathStr = [Environment]::GetEnvironmentVariable('Path', $User)
    $CurrentPathParts = $CurrentPathStr -split ";" | Where-Object { $_.Trim() -ne "" }
    
    $NewPathParts = @()
    $IsPathModified = $false

    Write-Host "Processing Environment Variables..." -ForegroundColor Cyan

    foreach ($item in $config) {
        $fullPath = Resolve-PathInput $item.Path
        
        if ($fullPath -ne "") {
            # --- PRE-CALCULATE STATES ---
            $needsEnvUpdate = $false
            if (-not [string]::IsNullOrWhiteSpace($item.EnvVar)) {
                $existingVal = [Environment]::GetEnvironmentVariable($item.EnvVar, $User)
                if ($existingVal -ne $fullPath) { $needsEnvUpdate = $true }
            }

            $needsPathUpdate = $false
            $targetPath = $fullPath
            
            if ($CurrentPathParts -notcontains $targetPath) { $needsPathUpdate = $true }

            # --- OUTPUT LOGIC ---
            if (-not $needsEnvUpdate -and -not $needsPathUpdate) {
                Write-Host "  * $($item.Label) - SKIPPED, already exists" -ForegroundColor DarkGray
            } else {
                Write-Host "  + $($item.Label)" -ForegroundColor White

                if ($needsEnvUpdate) {
                    # FIX: Use Registry helper
                    Set-RegistryEnv $item.EnvVar $fullPath
                    Write-Host "    + ENV: Setting $($item.EnvVar)" -ForegroundColor Green
                }

                if ($needsPathUpdate) {
                    $NewPathParts += $targetPath
                    Write-Host "    + PATH: Queuing '$targetPath'" -ForegroundColor Green
                    $IsPathModified = $true
                }
            }
        }
    }
    
    if ($IsPathModified) {
        $FinalPathString = ($NewPathParts -join ";") + ";" + $CurrentPathStr
        # FIX: Use Registry helper
        Set-RegistryEnv 'Path' $FinalPathString
        
        # Trigger Broadcast
        [Environment]::SetEnvironmentVariable('PORTAPATH_ACTIVE', "1", $User)
        Write-Host "`nSUCCESS: New paths injected." -ForegroundColor Green
    } else {
        Write-Host "`nNO CHANGES: Environment is already up to date." -ForegroundColor Yellow
    }
}

function Action-Deactivate {
    $config = Get-Config
    
    $User = [EnvironmentVariableTarget]::User
    
    $CurrentPathStr = [Environment]::GetEnvironmentVariable('Path', $User)
    [System.Collections.Generic.List[string]]$PathList = $CurrentPathStr -split ";" | Where-Object { $_.Trim() -ne "" }
    
    $IsPathModified = $false

    Write-Host "Checking for paths to remove..." -ForegroundColor Yellow

    # --- 1. SURGICAL REMOVAL (Known Config Items) ---
    foreach ($item in $config) {
        $fullPath = Resolve-PathInput $item.Path
        
        if ($fullPath -ne "") {
            $needsEnvRemove = $false
            if (-not [string]::IsNullOrWhiteSpace($item.EnvVar)) {
                if ([Environment]::GetEnvironmentVariable($item.EnvVar, $User) -ne $null) { 
                    $needsEnvRemove = $true 
                }
            }

            $targetBin  = "$fullPath\bin"
            $targetRoot = $fullPath
            $needsPathRemove = $false
            
            if ($PathList.Contains($targetBin) -or $PathList.Contains($targetRoot)) { 
                $needsPathRemove = $true 
            }

            if (-not $needsEnvRemove -and -not $needsPathRemove) {
                 Write-Host "  * $($item.Label) - SKIPPED, already clean" -ForegroundColor DarkGray
            } else {
                Write-Host "  + $($item.Label)" -ForegroundColor White

                if ($needsEnvRemove) {
                    [Environment]::SetEnvironmentVariable($item.EnvVar, $null, $User)
                    Write-Host "    - ENV: Removed $($item.EnvVar)" -ForegroundColor Red
                }

                if ($needsPathRemove) {
                    if ($PathList.Contains($targetBin)) {
                        [void]$PathList.Remove($targetBin)
                        Write-Host "    - PATH: Removed '$targetBin'" -ForegroundColor Red
                        $IsPathModified = $true
                    }
                    if ($PathList.Contains($targetRoot)) {
                        [void]$PathList.Remove($targetRoot)
                        Write-Host "    - PATH: Removed '$targetRoot'" -ForegroundColor Red
                        $IsPathModified = $true
                    }
                }
            }
        }
    }

    # --- 2. ORPHAN DETECTION (Interactive) ---
    # Find paths that are on THIS drive but were NOT in the config
    $DriveOrphans = @()
    foreach ($p in $PathList) {
        if ($p.StartsWith($driveRoot)) {
            $DriveOrphans += $p
        }
    }

    if ($DriveOrphans.Count -gt 0) {
        Write-Host "`n! WARNING: Found paths on this drive NOT in your config:" -ForegroundColor Magenta
        foreach ($orphan in $DriveOrphans) {
            Write-Host "  ? $orphan" -ForegroundColor Magenta
        }
        
        Write-Host "These might be tools you removed from the list but forgot to deactivate." -ForegroundColor Gray
        $confirmation = Read-Host "Do you want to remove them? (Y/N)"
        
        if ($confirmation -eq "Y" -or $confirmation -eq "y") {
            foreach ($orphan in $DriveOrphans) {
                [void]$PathList.Remove($orphan)
                Write-Host "    - REMOVED: $orphan" -ForegroundColor Red
            }
            $IsPathModified = $true
        } else {
            Write-Host "  * Skipping orphans." -ForegroundColor Gray
        }
    }

    # --- 3. COMMIT CHANGES ---
    if ($IsPathModified) {
        $FinalPathString = $PathList -join ";"
        [Environment]::SetEnvironmentVariable('Path', $FinalPathString, $User)
        [Environment]::SetEnvironmentVariable('PORTAPATH_ACTIVE', $null, $User)
        Write-Host "`nSUCCESS: Cleaned paths from environment." -ForegroundColor Green
    } else {
         Write-Host "`nCLEAN: No paths needed removal." -ForegroundColor Yellow
    }
}

# 3. MAIN EXECUTION FLOW
if ($args.Count -eq 0) {
    Write-Host "PortaPath CLI v1.0" -ForegroundColor White
    Write-Host "------------------" -ForegroundColor DarkGray
    Write-Host "Usage:"
    Write-Host "  list                   Show current config"
    Write-Host "  add <Name> <Path> [V]  Add new entry (V = EnvVar)"
    Write-Host "  remove <Name>          Remove entry by Name"
    Write-Host "  activate               Inject variables"
    Write-Host "  deactivate             Clean variables"
    exit
}

switch ($args[0].ToLower()) {
    "list"       { Action-List }
    "add"        { Action-Add $args[1] $args[2] $args[3] }
    "remove"     { Action-Remove $args[1] }
    "activate"   { Action-Activate }
    "deactivate" { Action-Deactivate }
    default      { Write-Error "Unknown command: '$($args[0])'. Use list, add, remove, activate, or deactivate." }
}