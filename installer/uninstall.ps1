<#
.SYNOPSIS
    FreshBooks MCP Uninstaller
    
.DESCRIPTION
    Comprehensive uninstaller for FreshBooks MCP that removes all components,
    registry entries, shortcuts, and application data.
    
.PARAMETER KeepData
    Preserve user data and configuration files during uninstall
    
.PARAMETER Silent
    Run uninstall without confirmation prompts (use with caution)
    
.PARAMETER LogPath
    Custom path for uninstall log file
    
.EXAMPLE
    .\uninstall.ps1
    
.EXAMPLE
    .\uninstall.ps1 -KeepData
    
.EXAMPLE
    .\uninstall.ps1 -Silent
    
.NOTES
    Author: Ehrig Consulting
    Version: 1.0.0
    Requires: PowerShell 5.1 or higher, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$KeepData,
    
    [Parameter(Mandatory=$false)]
    [switch]$Silent,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:TEMP\FreshBooksMCP_Uninstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Script configuration
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Application constants
$AppName = "FreshBooks MCP"
$CompanyName = "EhrigConsulting"
$InstallPath = "$env:ProgramFiles\FreshBooks MCP"
$AppDataPath = "$env:APPDATA\FreshBooksMCP"
$LocalAppDataPath = "$env:LOCALAPPDATA\FreshBooksMCP"
$StartMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\FreshBooks MCP"

# Backup storage for rollback
$script:BackupData = @{
    RegistryEntries = @()
    FilesRemoved = @()
    ShortcutsRemoved = @()
}

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes message to log file and console
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    
    # Write to console with colors
    switch ($Level) {
        'Info'    { Write-Host $Message -ForegroundColor Cyan }
        'Success' { Write-Host "✓ $Message" -ForegroundColor Green }
        'Warning' { Write-Host "⚠ $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "✗ $Message" -ForegroundColor Red }
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if script is running with administrator privileges
    #>
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminElevation {
    <#
    .SYNOPSIS
        Requests administrator elevation if not already running as admin
    #>
    if (-not (Test-Administrator)) {
        Write-Log "Administrator privileges required. Requesting elevation..." -Level Warning
        
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($KeepData) { $arguments += " -KeepData" }
        if ($Silent) { $arguments += " -Silent" }
        if ($LogPath) { $arguments += " -LogPath `"$LogPath`"" }
        
        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
            exit 0
        }
        catch {
            Write-Log "Failed to elevate privileges: $_" -Level Error
            exit 1
        }
    }
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
        Prompts user for confirmation before proceeding
    #>
    if ($Silent) {
        return $true
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "   FreshBooks MCP Uninstaller" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "This will remove:" -ForegroundColor Yellow
    Write-Host "  • Installed application files" -ForegroundColor Gray
    Write-Host "  • Registry entries" -ForegroundColor Gray
    Write-Host "  • Start Menu shortcuts" -ForegroundColor Gray
    
    if (-not $KeepData) {
        Write-Host "  • Application data and configuration" -ForegroundColor Gray
        Write-Host "  • License files" -ForegroundColor Gray
        Write-Host "  • Downloaded AI models" -ForegroundColor Gray
    }
    else {
        Write-Host "  • User data will be PRESERVED (KeepData enabled)" -ForegroundColor Green
    }
    
    Write-Host ""
    $response = Read-Host "Do you want to continue? (Y/N)"
    return ($response -eq 'Y' -or $response -eq 'y')
}

function Stop-FreshBooksServices {
    <#
    .SYNOPSIS
        Stops any running FreshBooks MCP services or processes
    #>
    Write-Log "Checking for running processes..." -Level Info
    
    $processNames = @(
        'FreshBooksMCP',
        'freshbooks-mcp',
        'fb-mcp'
    )
    
    $stoppedProcesses = 0
    
    foreach ($processName in $processNames) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        
        if ($processes) {
            foreach ($process in $processes) {
                try {
                    Write-Log "Stopping process: $($process.Name) (PID: $($process.Id))" -Level Info
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Start-Sleep -Seconds 1
                    $stoppedProcesses++
                }
                catch {
                    Write-Log "Failed to stop process $($process.Name): $_" -Level Warning
                }
            }
        }
    }
    
    if ($stoppedProcesses -gt 0) {
        Write-Log "Stopped $stoppedProcesses process(es)" -Level Success
        Start-Sleep -Seconds 2
    }
    else {
        Write-Log "No running processes found" -Level Info
    }
}

function Remove-RegistryEntries {
    <#
    .SYNOPSIS
        Removes FreshBooks MCP registry entries
    #>
    Write-Log "Removing registry entries..." -Level Info
    
    $registryPaths = @(
        "HKLM:\SOFTWARE\$CompanyName\FreshBooksMCP",
        "HKCU:\SOFTWARE\$CompanyName\FreshBooksMCP",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FreshBooksMCP",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FreshBooksMCP"
    )
    
    $removedCount = 0
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                # Backup registry key before removal
                $backupPath = "$env:TEMP\FreshBooksMCP_Registry_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
                
                # Export for backup
                $regKey = $regPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\' -replace 'HKCU:\\', 'HKEY_CURRENT_USER\'
                reg export $regKey $backupPath /y 2>&1 | Out-Null
                
                $script:BackupData.RegistryEntries += @{
                    Path = $regPath
                    BackupFile = $backupPath
                }
                
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed registry key: $regPath" -Level Success
                $removedCount++
            }
            catch {
                Write-Log "Failed to remove registry key ${regPath}: $_" -Level Warning
            }
        }
    }
    
    # Remove PATH entries if present
    try {
        Remove-FromPath
    }
    catch {
        Write-Log "Failed to remove PATH entries: $_" -Level Warning
    }
    
    Write-Log "Removed $removedCount registry key(s)" -Level Success
}

function Remove-FromPath {
    <#
    .SYNOPSIS
        Removes FreshBooks MCP from system PATH
    #>
    $pathTypes = @(
        @{ Scope = 'Machine'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' },
        @{ Scope = 'User'; Path = 'HKCU:\Environment' }
    )
    
    foreach ($pathType in $pathTypes) {
        try {
            $currentPath = [Environment]::GetEnvironmentVariable('Path', $pathType.Scope)
            
            if ($currentPath -and $currentPath -like "*FreshBooks MCP*") {
                $pathArray = $currentPath -split ';' | Where-Object {
                    $_ -and $_ -notlike "*FreshBooks MCP*"
                }
                
                $newPath = $pathArray -join ';'
                [Environment]::SetEnvironmentVariable('Path', $newPath, $pathType.Scope)
                
                Write-Log "Removed from $($pathType.Scope) PATH" -Level Success
            }
        }
        catch {
            Write-Log "Failed to update $($pathType.Scope) PATH: $_" -Level Warning
        }
    }
}

function Remove-InstallationFiles {
    <#
    .SYNOPSIS
        Removes installed application files
    #>
    Write-Log "Removing installation files..." -Level Info
    
    if (Test-Path $InstallPath) {
        try {
            # Get size before removal for reporting
            $size = (Get-ChildItem $InstallPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            
            $script:BackupData.FilesRemoved += @{
                Path = $InstallPath
                Size = $sizeMB
            }
            
            Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed installation directory ($sizeMB MB): $InstallPath" -Level Success
        }
        catch {
            Write-Log "Failed to remove installation directory: $_" -Level Error
            throw
        }
    }
    else {
        Write-Log "Installation directory not found: $InstallPath" -Level Warning
    }
}

function Remove-UserData {
    <#
    .SYNOPSIS
        Removes user data and configuration files
    #>
    if ($KeepData) {
        Write-Log "Preserving user data (KeepData enabled)" -Level Info
        return
    }
    
    Write-Log "Removing user data..." -Level Info
    
    $dataPaths = @(
        $AppDataPath,
        $LocalAppDataPath
    )
    
    $removedCount = 0
    $totalSize = 0
    
    foreach ($dataPath in $dataPaths) {
        if (Test-Path $dataPath) {
            try {
                # Calculate size
                $size = (Get-ChildItem $dataPath -Recurse -File -ErrorAction SilentlyContinue | 
                         Measure-Object -Property Length -Sum).Sum
                $sizeMB = [math]::Round($size / 1MB, 2)
                $totalSize += $sizeMB
                
                Remove-Item -Path $dataPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed data directory ($sizeMB MB): $dataPath" -Level Success
                $removedCount++
            }
            catch {
                Write-Log "Failed to remove data directory ${dataPath}: $_" -Level Warning
            }
        }
    }
    
    if ($removedCount -gt 0) {
        Write-Log "Removed $removedCount data director(ies), freed $totalSize MB" -Level Success
    }
}

function Remove-Shortcuts {
    <#
    .SYNOPSIS
        Removes Start Menu shortcuts and desktop icons
    #>
    Write-Log "Removing shortcuts..." -Level Info
    
    $shortcutPaths = @(
        $StartMenuPath,
        "$env:PUBLIC\Desktop\FreshBooks MCP.lnk",
        "$env:USERPROFILE\Desktop\FreshBooks MCP.lnk"
    )
    
    $removedCount = 0
    
    foreach ($shortcutPath in $shortcutPaths) {
        if (Test-Path $shortcutPath) {
            try {
                $script:BackupData.ShortcutsRemoved += $shortcutPath
                
                Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed shortcut: $shortcutPath" -Level Success
                $removedCount++
            }
            catch {
                Write-Log "Failed to remove shortcut ${shortcutPath}: $_" -Level Warning
            }
        }
    }
    
    if ($removedCount -eq 0) {
        Write-Log "No shortcuts found to remove" -Level Info
    }
    else {
        Write-Log "Removed $removedCount shortcut(s)" -Level Success
    }
}

function Remove-AIModels {
    <#
    .SYNOPSIS
        Removes downloaded AI models
    #>
    if ($KeepData) {
        return
    }
    
    Write-Log "Checking for AI models..." -Level Info
    
    $modelPaths = @(
        "$LocalAppDataPath\models",
        "$AppDataPath\models",
        "$InstallPath\models"
    )
    
    $removedSize = 0
    
    foreach ($modelPath in $modelPaths) {
        if (Test-Path $modelPath) {
            try {
                $size = (Get-ChildItem $modelPath -Recurse -File -ErrorAction SilentlyContinue | 
                         Measure-Object -Property Length -Sum).Sum
                $sizeMB = [math]::Round($size / 1MB, 2)
                
                Remove-Item -Path $modelPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed AI models ($sizeMB MB): $modelPath" -Level Success
                $removedSize += $sizeMB
            }
            catch {
                Write-Log "Failed to remove AI models from ${modelPath}: $_" -Level Warning
            }
        }
    }
    
    if ($removedSize -gt 0) {
        Write-Log "Freed $removedSize MB from AI models" -Level Success
    }
}

function Remove-WindowsInstallerEntry {
    <#
    .SYNOPSIS
        Removes entry from Windows Programs and Features
    #>
    Write-Log "Removing from Windows Programs list..." -Level Info
    
    # Already handled in Remove-RegistryEntries via Uninstall keys
    Write-Log "Windows Programs entry removed" -Level Success
}

function Test-UninstallSuccess {
    <#
    .SYNOPSIS
        Verifies that uninstall completed successfully
    #>
    Write-Log "Verifying uninstall..." -Level Info
    
    $issues = @()
    
    # Check installation directory
    if (Test-Path $InstallPath) {
        $issues += "Installation directory still exists: $InstallPath"
    }
    
    # Check registry
    $registryPaths = @(
        "HKLM:\SOFTWARE\$CompanyName\FreshBooksMCP",
        "HKCU:\SOFTWARE\$CompanyName\FreshBooksMCP"
    )
    
    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            $issues += "Registry key still exists: $regPath"
        }
    }
    
    # Check shortcuts
    if (Test-Path $StartMenuPath) {
        $issues += "Start Menu folder still exists: $StartMenuPath"
    }
    
    if ($issues.Count -gt 0) {
        Write-Log "Uninstall verification found issues:" -Level Warning
        foreach ($issue in $issues) {
            Write-Log "  - $issue" -Level Warning
        }
        return $false
    }
    else {
        Write-Log "Uninstall verification successful" -Level Success
        return $true
    }
}

function Invoke-Rollback {
    <#
    .SYNOPSIS
        Attempts to rollback changes if uninstall fails
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorMessage
    )
    
    Write-Log "Uninstall failed: $ErrorMessage" -Level Error
    Write-Log "Attempting rollback..." -Level Warning
    
    # Restore registry entries
    foreach ($regEntry in $script:BackupData.RegistryEntries) {
        if (Test-Path $regEntry.BackupFile) {
            try {
                reg import $regEntry.BackupFile 2>&1 | Out-Null
                Write-Log "Restored registry: $($regEntry.Path)" -Level Success
            }
            catch {
                Write-Log "Failed to restore registry: $($regEntry.Path)" -Level Error
            }
        }
    }
    
    Write-Log "Rollback completed. Application may be in inconsistent state." -Level Warning
    Write-Log "Please contact support or retry uninstall." -Level Info
}

function Write-UninstallSummary {
    <#
    .SYNOPSIS
        Displays summary of uninstall operation
    #>
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "   Uninstall Summary" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
    
    Write-Host "Registry Entries Removed: " -NoNewline -ForegroundColor Gray
    Write-Host $script:BackupData.RegistryEntries.Count -ForegroundColor White
    
    Write-Host "Shortcuts Removed: " -NoNewline -ForegroundColor Gray
    Write-Host $script:BackupData.ShortcutsRemoved.Count -ForegroundColor White
    
    $totalSize = ($script:BackupData.FilesRemoved | Measure-Object -Property Size -Sum).Sum
    Write-Host "Disk Space Freed: " -NoNewline -ForegroundColor Gray
    Write-Host "$([math]::Round($totalSize, 2)) MB" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Log file: " -NoNewline -ForegroundColor Gray
    Write-Host $LogPath -ForegroundColor Cyan
    
    if ($KeepData) {
        Write-Host ""
        Write-Host "User data preserved in:" -ForegroundColor Yellow
        if (Test-Path $AppDataPath) {
            Write-Host "  $AppDataPath" -ForegroundColor Gray
        }
        if (Test-Path $LocalAppDataPath) {
            Write-Host "  $LocalAppDataPath" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
}

#endregion

#region Main Execution

try {
    # Initialize log
    Write-Log "FreshBooks MCP Uninstaller v1.0.0" -Level Info
    Write-Log "Log file: $LogPath" -Level Info
    Write-Log "Keep Data: $KeepData | Silent: $Silent" -Level Info
    Write-Log "" -Level Info
    
    # Check administrator privileges
    Request-AdminElevation
    
    # Get user confirmation
    if (-not (Get-UserConfirmation)) {
        Write-Log "Uninstall cancelled by user" -Level Warning
        exit 0
    }
    
    Write-Host ""
    Write-Log "Starting uninstall process..." -Level Info
    Write-Host ""
    
    # Execute uninstall steps
    $steps = @(
        @{ Name = "Stopping processes"; Action = { Stop-FreshBooksServices } },
        @{ Name = "Removing shortcuts"; Action = { Remove-Shortcuts } },
        @{ Name = "Removing installation files"; Action = { Remove-InstallationFiles } },
        @{ Name = "Removing user data"; Action = { Remove-UserData } },
        @{ Name = "Removing AI models"; Action = { Remove-AIModels } },
        @{ Name = "Removing registry entries"; Action = { Remove-RegistryEntries } },
        @{ Name = "Removing from Programs list"; Action = { Remove-WindowsInstallerEntry } }
    )
    
    $currentStep = 0
    $totalSteps = $steps.Count
    
    foreach ($step in $steps) {
        $currentStep++
        $percentComplete = [math]::Round(($currentStep / $totalSteps) * 100)
        
        Write-Progress -Activity "Uninstalling FreshBooks MCP" `
                       -Status "$($step.Name) ($currentStep of $totalSteps)" `
                       -PercentComplete $percentComplete
        
        Write-Host ""
        Write-Log "[$currentStep/$totalSteps] $($step.Name)..." -Level Info
        
        try {
            & $step.Action
        }
        catch {
            Write-Log "Step failed: $($step.Name)" -Level Error
            Invoke-Rollback -ErrorMessage $_.Exception.Message
            exit 1
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    Write-Progress -Activity "Uninstalling FreshBooks MCP" -Completed
    
    # Verify uninstall
    Write-Host ""
    $success = Test-UninstallSuccess
    
    # Display summary
    Write-Host ""
    Write-UninstallSummary
    
    if ($success) {
        Write-Host ""
        Write-Host "✓ FreshBooks MCP has been successfully uninstalled!" -ForegroundColor Green
        Write-Host ""
        
        if (-not $Silent) {
            Write-Host "Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        
        exit 0
    }
    else {
        Write-Host ""
        Write-Host "⚠ Uninstall completed with warnings. Please review log file." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}
catch {
    Write-Log "Critical error during uninstall: $_" -Level Error
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
    
    Invoke-Rollback -ErrorMessage $_.Exception.Message
    
    Write-Host ""
    Write-Host "✗ Uninstall failed. See log file for details: $LogPath" -ForegroundColor Red
    Write-Host ""
    
    if (-not $Silent) {
        Write-Host "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    
    exit 1
}

#endregion
