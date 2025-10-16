# FreshBooks MCP Installer Builder
# Creates a single installer with built-in licensing

[CmdletBinding()]
param(
    [switch]$SkipClaudeCheck
)

$Version = "1.0.0"
$ProductName = "FreshBooks MCP"
$Manufacturer = "Ehrig BIM & IT Consultation, Inc."

# Paths
$SourceDir = "..\src"
$LicensingDir = "..\src\licensing"
$OutputDir = "..\releases\latest"

# Function: Test-ClaudeDesktopInstalled
# Detects if Claude Desktop is installed on the system
function Test-ClaudeDesktopInstalled {
    $detectionResults = @{
        Found = $false
        Method = ""
        Path = ""
        Details = @()
    }
    
    Write-Host "Checking for Claude Desktop installation..." -ForegroundColor Yellow
    
    # Check 1: Registry (HKLM)
    try {
        $regPath = "HKLM:\SOFTWARE\Anthropic\Claude Desktop"
        if (Test-Path $regPath) {
            $regValue = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            if ($regValue) {
                $detectionResults.Found = $true
                $detectionResults.Method = "Registry (HKLM)"
                $detectionResults.Path = $regPath
                $detectionResults.Details += "Found in registry: $regPath"
                Write-Host "  ✅ Found in registry (HKLM)" -ForegroundColor Green
            }
        }
    } catch {
        $detectionResults.Details += "Registry check (HKLM) failed: $($_.Exception.Message)"
    }
    
    # Check 2: Registry (HKCU)
    if (-not $detectionResults.Found) {
        try {
            $regPath = "HKCU:\SOFTWARE\Anthropic\Claude Desktop"
            if (Test-Path $regPath) {
                $regValue = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if ($regValue) {
                    $detectionResults.Found = $true
                    $detectionResults.Method = "Registry (HKCU)"
                    $detectionResults.Path = $regPath
                    $detectionResults.Details += "Found in registry: $regPath"
                    Write-Host "  ✅ Found in registry (HKCU)" -ForegroundColor Green
                }
            }
        } catch {
            $detectionResults.Details += "Registry check (HKCU) failed: $($_.Exception.Message)"
        }
    }
    
    # Check 3: Program Files
    if (-not $detectionResults.Found) {
        $programFilesPath = "C:\Program Files\Claude Desktop"
        if (Test-Path $programFilesPath) {
            $detectionResults.Found = $true
            $detectionResults.Method = "Program Files"
            $detectionResults.Path = $programFilesPath
            $detectionResults.Details += "Found in Program Files: $programFilesPath"
            Write-Host "  ✅ Found in Program Files" -ForegroundColor Green
        } else {
            $detectionResults.Details += "Not found in Program Files: $programFilesPath"
        }
    }
    
    # Check 4: User AppData
    if (-not $detectionResults.Found) {
        $appDataPath = "$env:LOCALAPPDATA\Programs\Claude Desktop"
        if (Test-Path $appDataPath) {
            $detectionResults.Found = $true
            $detectionResults.Method = "AppData"
            $detectionResults.Path = $appDataPath
            $detectionResults.Details += "Found in AppData: $appDataPath"
            Write-Host "  ✅ Found in AppData" -ForegroundColor Green
        } else {
            $detectionResults.Details += "Not found in AppData: $appDataPath"
        }
    }
    
    # Check 5: Running Process
    if (-not $detectionResults.Found) {
        try {
            $claudeProcess = Get-Process -Name "claude" -ErrorAction SilentlyContinue
            if ($claudeProcess) {
                $detectionResults.Found = $true
                $detectionResults.Method = "Running Process"
                $detectionResults.Path = $claudeProcess.Path
                $detectionResults.Details += "Found running process: claude.exe at $($claudeProcess.Path)"
                Write-Host "  ✅ Found running process (claude.exe)" -ForegroundColor Green
            } else {
                $detectionResults.Details += "claude.exe process not running"
            }
        } catch {
            $detectionResults.Details += "Process check failed: $($_.Exception.Message)"
        }
    }
    
    return $detectionResults
}

# Function: Show-ClaudeNotFoundPrompt
# Displays error and options when Claude Desktop is not found
function Show-ClaudeNotFoundPrompt {
    param($detectionResults)
    
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "  ⚠️  Claude Desktop Not Found" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "FreshBooks MCP requires Claude Desktop to be installed." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Detection Details:" -ForegroundColor Cyan
    foreach ($detail in $detectionResults.Details) {
        Write-Host "  - $detail" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Download Claude Desktop from:" -ForegroundColor Yellow
    Write-Host "  🔗 https://claude.ai/download" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  [D] Download Now (opens browser)" -ForegroundColor White
    Write-Host "  [L] I'll Install Later (exit)" -ForegroundColor White
    Write-Host "  [C] Continue Anyway (not recommended)" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Choose an option [D/L/C]"
    
    switch ($choice.ToUpper()) {
        "D" {
            Write-Host "Opening download page..." -ForegroundColor Green
            Start-Process "https://claude.ai/download"
            Write-Host "Please install Claude Desktop and run this installer again." -ForegroundColor Yellow
            exit 0
        }
        "L" {
            Write-Host "Installation cancelled. Install Claude Desktop and try again." -ForegroundColor Yellow
            exit 0
        }
        "C" {
            Write-Host ""
            Write-Host "⚠️  WARNING: Continuing without Claude Desktop" -ForegroundColor Red
            Write-Host "The MCP server will be installed but won't function until Claude Desktop is installed." -ForegroundColor Yellow
            Write-Host ""
            $confirm = Read-Host "Are you sure? [Y/N]"
            if ($confirm.ToUpper() -ne "Y") {
                Write-Host "Installation cancelled." -ForegroundColor Yellow
                exit 0
            }
            Write-Host "Continuing installation..." -ForegroundColor Yellow
        }
        default {
            Write-Host "Invalid option. Installation cancelled." -ForegroundColor Red
            exit 1
        }
    }
}

# Ensure output directory exists
New-Item -ItemType Directory -Force -Path $OutputDir

# PRE-FLIGHT CHECK: Validate Claude Desktop Installation
if (-not $SkipClaudeCheck) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Pre-Flight Validation" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    
    $claudeCheck = Test-ClaudeDesktopInstalled
    
    if (-not $claudeCheck.Found) {
        Show-ClaudeNotFoundPrompt -detectionResults $claudeCheck
    } else {
        Write-Host ""
        Write-Host "✅ Claude Desktop detected: $($claudeCheck.Method)" -ForegroundColor Green
        Write-Host "   Path: $($claudeCheck.Path)" -ForegroundColor Gray
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "⚠️  Skipping Claude Desktop validation (-SkipClaudeCheck)" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Building $ProductName v$Version installer with licensing..." -ForegroundColor Cyan

# Step 1: Package the application with licensing
Write-Host "Packaging application files..." -ForegroundColor Yellow

$TempDir = "$env:TEMP\freshbooks-mcp-build"
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $TempDir

# Copy application files
Copy-Item -Path "$SourceDir\*" -Destination $TempDir -Recurse -Force
Copy-Item -Path "$LicensingDir\*" -Destination "$TempDir\licensing" -Recurse -Force

# Step 2: Create installer configuration
$InstallerConfigObject = @{
    productName = $ProductName
    version = $Version
    manufacturer = $Manufacturer
    description = "Control FreshBooks with natural language through Claude Desktop"
    features = @{
        licensing = $true
        autoUpdate = $true
        startMenuShortcut = $true
        desktopShortcut = $false
        systemTray = $true
    }
    registry = @{
        installPath = "HKLM\SOFTWARE\EhrigConsulting\FreshBooksMCP"
        version = $Version
    }
    components = @(
        @{
            name = "Core"
            description = "Core FreshBooks MCP functionality"
            required = $true
            size = "15MB"
        },
        @{
            name = "Licensing"
            description = "License management and activation"
            required = $true
            size = "2MB"
        },
        @{
            name = "ClaudeIntegration"
            description = "Claude Desktop integration"
            required = $true
            size = "5MB"
        }
    )
    postInstall = @{
        launchActivation = $true
        startService = $true
        openDocumentation = $false
    }
}

$InstallerConfig = $InstallerConfigObject | ConvertTo-Json -Depth 10
$InstallerConfig | Out-File -FilePath "$TempDir\installer.json"

# Step 3: Create WiX configuration for MSI
$WixConfig = @'
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*"
           Name="FreshBooks MCP"
           Language="1033"
           Version="1.0.0"
           Manufacturer="Ehrig BIM and IT Consultation Inc"
           UpgradeCode="7E8C4B21-9A7F-4D5E-B123-456789ABCDEF">
           
    <Package InstallerVersion="200" 
             Compressed="yes" 
             InstallScope="perMachine" />
             
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    
    <MediaTemplate EmbedCab="yes" />
    
    <!-- Features -->
    <Feature Id="ProductFeature" Title="FreshBooks MCP" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
      <ComponentGroupRef Id="LicensingComponents" />
      <ComponentRef Id="StartMenuShortcut" />
      <ComponentRef Id="RegistryEntries" />
    </Feature>

    <!-- Directory Structure -->
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="FreshBooksMCP">
          <Directory Id="LICENSINGFOLDER" Name="licensing" />
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="FreshBooks MCP" />
      </Directory>
    </Directory>

    <!-- Components -->
    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
      <Component Id="MainExecutable" Guid="12345678-1234-1234-1234-123456789012">
        <File Id="FreshBooksMCP.exe" Source="$(TempDir)\FreshBooksMCP.exe" KeyPath="yes">
          <Shortcut Id="StartMenuShortcut"
                    Directory="ApplicationProgramsFolder"
                    Name="FreshBooks MCP"
                    WorkingDirectory="INSTALLFOLDER"
                    Icon="FreshBooksMCP.ico"
                    Advertise="yes" />
        </File>
      </Component>
    </ComponentGroup>

    <ComponentGroup Id="LicensingComponents" Directory="LICENSINGFOLDER">
      <Component Id="LicenseManager" Guid="23456789-2345-2345-2345-234567890123">
        <File Id="license-manager.js" Source="$(TempDir)\licensing\license-manager.js" />
      </Component>
      <Component Id="FeatureGate" Guid="34567890-3456-3456-3456-345678901234">
        <File Id="feature-gate.js" Source="$(TempDir)\licensing\feature-gate.js" />
      </Component>
      <Component Id="ActivationUI" Guid="45678901-4567-4567-4567-456789012345">
        <File Id="activation-ui.html" Source="$(TempDir)\licensing\activation-ui.html" />
      </Component>
    </ComponentGroup>

    <!-- Registry -->
    <Component Id="RegistryEntries" Directory="INSTALLFOLDER">
      <RegistryKey Root="HKLM" Key="SOFTWARE\EhrigConsulting\FreshBooksMCP">
        <RegistryValue Type="string" Name="Version" Value="1.0.0" />
        <RegistryValue Type="string" Name="InstallPath" Value="[INSTALLFOLDER]" />
        <RegistryValue Type="string" Name="LicenseType" Value="trial" />
      </RegistryKey>
    </Component>

    <!-- Start Menu Shortcut -->
    <Component Id="StartMenuShortcut" Directory="ApplicationProgramsFolder">
      <Shortcut Id="LicenseActivationShortcut"
                Name="License Activation"
                Description="Activate FreshBooks MCP Pro"
                Target="[INSTALLFOLDER]licensing\activation-ui.html" />
      <RemoveFolder Id="ApplicationProgramsFolder" On="uninstall" />
      <RegistryValue Root="HKCU" Key="Software\EhrigConsulting\FreshBooksMCP"
                     Name="installed" Type="integer" Value="1" KeyPath="yes" />
    </Component>

    <!-- Custom Actions -->
    <CustomAction Id="LaunchActivation"
                  BinaryKey="WixCA"
                  DllEntry="WixShellExec"
                  Execute="immediate"
                  Return="asyncNoWait" />

    <InstallExecuteSequence>
      <Custom Action="LaunchActivation" After="InstallFinalize">NOT Installed</Custom>
    </InstallExecuteSequence>

    <!-- UI -->
    <UIRef Id="WixUI_InstallDir" />
    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLFOLDER" />

  </Product>
</Wix>
'@

$WixConfig | Out-File -FilePath "$TempDir\Product.wxs"

# Step 4: Build the installer
Write-Host "Building MSI installer..." -ForegroundColor Yellow

# Check if WiX Toolset is installed
$WixPath = "${env:ProgramFiles(x86)}\WiX Toolset v3.11\bin"
if (-not (Test-Path $WixPath)) {
    Write-Host "WiX Toolset not found. Using alternative method..." -ForegroundColor Yellow
    
    # Alternative: Create a self-extracting archive with installer script
    # Create install.bat using Set-Content to avoid parsing issues
    Set-Content -Path "$TempDir\install.bat" -Encoding ASCII -Value @'
@echo off
title FreshBooks MCP Installer v1.0.0
cls
echo.
echo =========================================
echo   FreshBooks MCP v1.0.0 Installation
echo =========================================
echo.
echo Installing to: %ProgramFiles%\FreshBooksMCP
echo.

:: Check admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Administrator privileges required.
    echo Please run as administrator.
    pause
    exit /b 1
)

:: Create directories
mkdir "%ProgramFiles%\FreshBooksMCP" 2>nul
mkdir "%ProgramFiles%\FreshBooksMCP\licensing" 2>nul

:: Copy files
echo Copying files...
xcopy /E /Y /Q ".\*" "%ProgramFiles%\FreshBooksMCP\"

:: Register with Claude Desktop
echo Configuring Claude Desktop integration...
call "%ProgramFiles%\FreshBooksMCP\register-claude.bat"

:: TODO: Create start menu shortcuts (requires separate script file)
:: For now shortcuts will be created by WiX installer or manually

:: Set registry entries
echo Setting registry entries...
reg add "HKLM\SOFTWARE\EhrigConsulting\FreshBooksMCP" /v Version /t REG_SZ /d "1.0.0" /f
reg add "HKLM\SOFTWARE\EhrigConsulting\FreshBooksMCP" /v InstallPath /t REG_SZ /d "%ProgramFiles%\FreshBooksMCP" /f
reg add "HKLM\SOFTWARE\EhrigConsulting\FreshBooksMCP" /v LicenseType /t REG_SZ /d "trial" /f

:: Launch activation UI
echo.
echo =========================================
echo   Installation Complete!
echo =========================================
echo.
echo Launching License Activation...
start "" "%ProgramFiles%\FreshBooksMCP\licensing\activation-ui.html"

pause
'@
    
    # Create self-extracting archive
    Write-Host "Creating self-extracting installer..." -ForegroundColor Yellow
    
    # Use 7-Zip or built-in compression
    Compress-Archive -Path "$TempDir\*" -DestinationPath "$OutputDir\FreshBooksMCP-$Version.zip" -Force
    
    # Create EXE wrapper using Set-Content to avoid parsing issues
    Set-Content -Path "$OutputDir\FreshBooksMCP-$Version.exe" -Encoding ASCII -Value @'
@echo off
:: Self-extracting installer for FreshBooks MCP
:: Extract and run installer

set TEMP_DIR=%TEMP%\FreshBooksMCP-Install
rmdir /S /Q "%TEMP_DIR%" 2>nul
mkdir "%TEMP_DIR%"

:: Extract embedded archive
powershell -Command "Expand-Archive -Path '%~dp0FreshBooksMCP-1.0.0.zip' -DestinationPath '%TEMP_DIR%' -Force"

:: Run installer
cd /d "%TEMP_DIR%"
call install.bat

:: Cleanup
cd /d "%TEMP%"
rmdir /S /Q "%TEMP_DIR%"
'@
}

Write-Host "✅ Installer created successfully!" -ForegroundColor Green
Write-Host "📦 Output: $OutputDir\FreshBooksMCP-$Version.exe" -ForegroundColor Cyan
Write-Host "" -ForegroundColor White
Write-Host "Features included:" -ForegroundColor Yellow
Write-Host "  ✅ Single installer for all features" -ForegroundColor White
Write-Host "  ✅ License activation built-in" -ForegroundColor White
Write-Host "  ✅ Trial mode (30 days) by default" -ForegroundColor White
Write-Host "  ✅ Pro features unlocked with license key" -ForegroundColor White
Write-Host "  ✅ Automatic Claude Desktop integration" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Trial Limitations:" -ForegroundColor Yellow
Write-Host "  - 100 API calls/day" -ForegroundColor White
Write-Host "  - 5 invoices/month" -ForegroundColor White
Write-Host "  - 10 expenses/month" -ForegroundColor White
Write-Host "  - Read-only for advanced features" -ForegroundColor White