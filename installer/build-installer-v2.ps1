# Build Installer v2 - Simplified ZIP-based Installer
# Avoids complex here-strings and PowerShell parsing issues
# Creates a distributable ZIP package with all required components

param(
    [string]$Version = "1.0.0",
    [string]$OutputDir = ".\releases"
)

# Script configuration
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Color output helpers
function Write-Success { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-Header {
    param($msg)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "  $msg" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host ""
}

# Start build process
Write-Header "FreshBooks MCP Installer Build v2"
Write-Info "Version: $Version"
Write-Info "Output Directory: $OutputDir"

# Step 1: Verify project root
Write-Info "Verifying project structure..."
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path "$projectRoot\package.json")) {
    Write-Error "package.json not found at $projectRoot"
    exit 1
}
Write-Success "Project root validated: $projectRoot"

# Step 2: Create build directories
Write-Info "Creating build directories..."
$buildDir = Join-Path $env:TEMP "freshbooks-mcp-build-$(Get-Date -Format 'yyyyMMddHHmmss')"
$packageDir = Join-Path $buildDir "freshbooks-mcp-v$Version"
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Write-Success "Build directory: $buildDir"

# Step 3: Copy source files
Write-Info "Copying source files..."
$itemsToCopy = @(
    @{ Path = "src"; Type = "Directory" },
    @{ Path = "docs"; Type = "Directory" },
    @{ Path = "package.json"; Type = "File" },
    @{ Path = "package-lock.json"; Type = "File"; Optional = $true },
    @{ Path = "LICENSE"; Type = "File" },
    @{ Path = "SECURITY.md"; Type = "File" },
    @{ Path = "README.md"; Type = "File" }
)

foreach ($item in $itemsToCopy) {
    $sourcePath = Join-Path $projectRoot $item.Path
    if (Test-Path $sourcePath) {
        if ($item.Type -eq "Directory") {
            Copy-Item -Path $sourcePath -Destination $packageDir -Recurse -Force
            Write-Success "Copied directory: $($item.Path)"
        } else {
            Copy-Item -Path $sourcePath -Destination $packageDir -Force
            Write-Success "Copied file: $($item.Path)"
        }
    } elseif (-not $item.Optional) {
        Write-Error "Required item not found: $($item.Path)"
        exit 1
    }
}

# Step 4: Create installer scripts directory
Write-Info "Creating installer scripts..."
$scriptsDir = Join-Path $packageDir "installer"
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null

# Copy existing installer scripts
Copy-Item -Path "$projectRoot\installer\uninstall.ps1" -Destination $scriptsDir -Force
Write-Success "Copied uninstall.ps1"

# Step 5: Create simple install.ps1 script (write to file directly)
Write-Info "Generating install.ps1..."
$installScriptPath = Join-Path $packageDir "install.ps1"

# Build install script content line by line to avoid here-string issues
$lines = @()
$lines += '# FreshBooks MCP Installer'
$lines += '# Simple installation script'
$lines += ''
$lines += 'param('
$lines += '    [switch]$SkipClaudeCheck'
$lines += ')'
$lines += ''
$lines += '$ErrorActionPreference = "Stop"'
$lines += ''
$lines += 'Write-Host ""'
$lines += 'Write-Host "======================================" -ForegroundColor Cyan'
$lines += 'Write-Host "  FreshBooks MCP Installer" -ForegroundColor Cyan'
$lines += 'Write-Host "======================================" -ForegroundColor Cyan'
$lines += 'Write-Host ""'
$lines += ''
$lines += '# Check if Claude Desktop is installed'
$lines += 'if (-not $SkipClaudeCheck) {'
$lines += '    Write-Host "[INFO] Checking for Claude Desktop..." -ForegroundColor Cyan'
$lines += '    $claudeConfig = "$env:APPDATA\Claude\claude_desktop_config.json"'
$lines += '    if (-not (Test-Path $claudeConfig)) {'
$lines += '        Write-Host "[WARN] Claude Desktop not found!" -ForegroundColor Yellow'
$lines += '        Write-Host "Please install Claude Desktop first from:" -ForegroundColor Yellow'
$lines += '        Write-Host "https://claude.ai/download" -ForegroundColor Yellow'
$lines += '        $continue = Read-Host "Continue anyway? (y/n)"'
$lines += '        if ($continue -ne "y") { exit 1 }'
$lines += '    } else {'
$lines += '        Write-Host "[OK] Claude Desktop found" -ForegroundColor Green'
$lines += '    }'
$lines += '}'
$lines += ''
$lines += '# Get installation directory'
$lines += '$defaultPath = "$env:LOCALAPPDATA\freshbooks-mcp"'
$lines += '$installPath = Read-Host "Installation path [$defaultPath]"'
$lines += 'if ([string]::IsNullOrWhiteSpace($installPath)) {'
$lines += '    $installPath = $defaultPath'
$lines += '}'
$lines += ''
$lines += 'Write-Host "[INFO] Installing to: $installPath" -ForegroundColor Cyan'
$lines += ''
$lines += '# Create installation directory'
$lines += 'if (-not (Test-Path $installPath)) {'
$lines += '    New-Item -ItemType Directory -Force -Path $installPath | Out-Null'
$lines += '}'
$lines += ''
$lines += '# Copy files'
$lines += '$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path'
$lines += 'Write-Host "[INFO] Copying files..." -ForegroundColor Cyan'
$lines += 'Copy-Item -Path "$scriptDir\*" -Destination $installPath -Recurse -Force -Exclude @("install.ps1", "installer")'
$lines += ''
$lines += '# Install npm dependencies'
$lines += 'Write-Host "[INFO] Installing dependencies..." -ForegroundColor Cyan'
$lines += 'Push-Location $installPath'
$lines += 'try {'
$lines += '    npm install --production 2>&1 | Out-Null'
$lines += '    Write-Host "[OK] Dependencies installed" -ForegroundColor Green'
$lines += '} catch {'
$lines += '    Write-Host "[WARN] Failed to install dependencies: $_" -ForegroundColor Yellow'
$lines += '} finally {'
$lines += '    Pop-Location'
$lines += '}'
$lines += ''
$lines += '# Create start script'
$lines += '$startScript = "@echo off`r`ncd /d `"%~dp0`"`r`nnode src\index.js"'
$lines += '$startScript | Out-File -FilePath "$installPath\start.cmd" -Encoding ASCII'
$lines += ''
$lines += 'Write-Host ""'
$lines += 'Write-Host "[OK] Installation complete!" -ForegroundColor Green'
$lines += 'Write-Host ""'
$lines += 'Write-Host "Installation path: $installPath" -ForegroundColor Cyan'
$lines += 'Write-Host "Start command: $installPath\start.cmd" -ForegroundColor Cyan'
$lines += 'Write-Host ""'
$lines += 'Write-Host "Next steps:" -ForegroundColor Yellow'
$lines += 'Write-Host "1. Configure your FreshBooks API credentials" -ForegroundColor Yellow'
$lines += 'Write-Host "2. Add to Claude Desktop configuration" -ForegroundColor Yellow'
$lines += 'Write-Host "3. Run: $installPath\start.cmd" -ForegroundColor Yellow'
$lines += 'Write-Host ""'
$lines += 'pause'

# Write install script
[System.IO.File]::WriteAllLines($installScriptPath, $lines)
Write-Success "Created install.ps1"

# Step 6: Create README for installer
Write-Info "Creating installer README..."
$readmeLines = @()
$readmeLines += '# FreshBooks MCP Installer Package'
$readmeLines += ''
$readmeLines += '## Quick Start'
$readmeLines += ''
$readmeLines += '1. Extract this archive to a temporary location'
$readmeLines += '2. Right-click install.ps1 and select "Run with PowerShell"'
$readmeLines += '3. Follow the on-screen prompts'
$readmeLines += ''
$readmeLines += '## System Requirements'
$readmeLines += ''
$readmeLines += '- Windows 10/11'
$readmeLines += '- Node.js 18.0.0 or higher'
$readmeLines += '- Claude Desktop (recommended)'
$readmeLines += ''
$readmeLines += '## Installation Steps'
$readmeLines += ''
$readmeLines += '### Automatic Installation (Recommended)'
$readmeLines += ''
$readmeLines += '```powershell'
$readmeLines += '.\install.ps1'
$readmeLines += '```'
$readmeLines += ''
$readmeLines += '### Manual Installation'
$readmeLines += ''
$readmeLines += '1. Copy the contents to your desired installation directory'
$readmeLines += '2. Open PowerShell in that directory'
$readmeLines += '3. Run: npm install --production'
$readmeLines += '4. Configure your FreshBooks API credentials'
$readmeLines += '5. Start the server: node src\index.js'
$readmeLines += ''
$readmeLines += '## Support'
$readmeLines += ''
$readmeLines += '- Documentation: See docs/ folder'
$readmeLines += '- Issues: https://github.com/ehrigconsulting/freshbooks-mcp-public/issues'
$readmeLines += '- Email: support@ehrigconsulting.com'

$readmePath = Join-Path $packageDir "README.txt"
[System.IO.File]::WriteAllLines($readmePath, $readmeLines)
Write-Success "Created README.txt"

# Step 7: Create version info file
Write-Info "Creating version info..."
$versionInfo = @{
    version = $Version
    buildDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    buildNumber = (Get-Date).ToString("yyyyMMddHHmmss")
    platform = "windows"
    nodeVersion = ">=18.0.0"
} | ConvertTo-Json -Depth 10

$versionInfo | Out-File -FilePath "$packageDir\version.json" -Encoding UTF8
Write-Success "Created version.json"

# Step 8: Create ZIP archive
Write-Info "Creating ZIP archive..."
$zipFileName = "freshbooks-mcp-v$Version-windows-x64.zip"
$zipPath = Join-Path $OutputDir $zipFileName

# Remove existing ZIP if present
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
    Write-Warning "Removed existing ZIP: $zipFileName"
}

# Create ZIP using .NET compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($packageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Write-Success "Created ZIP: $zipFileName"

# Step 9: Generate checksums
Write-Info "Generating checksums..."
$zipFile = Get-Item $zipPath

# Try Get-FileHash, fallback to certutil if not available
try {
    $hash = Get-FileHash -Path $zipPath -Algorithm SHA256
    $hashValue = $hash.Hash
} catch {
    Write-Info "Using certutil for checksum generation..."
    $certutilOutput = certutil -hashfile $zipPath SHA256 2>&1
    $hashValue = ($certutilOutput | Select-Object -Skip 1 -First 1).Trim()
}

$checksumLines = @()
$checksumLines += "FreshBooks MCP v$Version - Release Checksums"
$checksumLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$checksumLines += ""
$checksumLines += "File: $zipFileName"
$checksumLines += "Size: $([math]::Round($zipFile.Length / 1MB, 2)) MB"
$checksumLines += "SHA256: $hashValue"
$checksumLines += ""
$checksumLines += "Verification:"
$checksumLines += "  Windows: certutil -hashfile `"$zipFileName`" SHA256"
$checksumLines += "  PowerShell: (Get-FileHash `"$zipFileName`" -Algorithm SHA256).Hash"

$checksumPath = Join-Path $OutputDir "checksums-v$Version.txt"
[System.IO.File]::WriteAllLines($checksumPath, $checksumLines)
Write-Success "Created checksums file"

# Step 10: Create quick-start guide
Write-Info "Creating quick-start guide..."
$quickStartLines = @()
$quickStartLines += "FreshBooks MCP v$Version - Quick Start Guide"
$quickStartLines += "============================================"
$quickStartLines += ""
$quickStartLines += "Installation"
$quickStartLines += "------------"
$quickStartLines += "1. Extract $zipFileName"
$quickStartLines += "2. Right-click install.ps1 and select `"Run with PowerShell`""
$quickStartLines += "3. Follow installation prompts"
$quickStartLines += ""
$quickStartLines += "Verification"
$quickStartLines += "------------"
$quickStartLines += "SHA256: $hashValue"
$quickStartLines += ""
$quickStartLines += "Verify with:"
$quickStartLines += "  certutil -hashfile `"$zipFileName`" SHA256"
$quickStartLines += ""
$quickStartLines += "First Run"
$quickStartLines += "---------"
$quickStartLines += "1. Configure FreshBooks API credentials"
$quickStartLines += "2. Add to Claude Desktop config"
$quickStartLines += "3. Start the MCP server"
$quickStartLines += ""
$quickStartLines += "Support"
$quickStartLines += "-------"
$quickStartLines += "Email: support@ehrigconsulting.com"
$quickStartLines += "GitHub: https://github.com/ehrigconsulting/freshbooks-mcp-public"

$quickStartPath = Join-Path $OutputDir "QUICK-START-v$Version.txt"
[System.IO.File]::WriteAllLines($quickStartPath, $quickStartLines)
Write-Success "Created quick-start guide"

# Step 11: Cleanup
Write-Info "Cleaning up temporary files..."
Remove-Item -Path $buildDir -Recurse -Force
Write-Success "Cleanup complete"

# Step 12: Build summary
Write-Header "Build Complete!"

Write-Host ""
Write-Host "Output Files:" -ForegroundColor Cyan
Write-Host "  ZIP Package: $zipPath" -ForegroundColor White
Write-Host "  Size: $([math]::Round($zipFile.Length / 1MB, 2)) MB" -ForegroundColor White
Write-Host "  SHA256: $hashValue" -ForegroundColor Gray
Write-Host ""
Write-Host "  Checksums: $checksumPath" -ForegroundColor White
Write-Host "  Quick Start: $quickStartPath" -ForegroundColor White
Write-Host ""

Write-Host "Distribution:" -ForegroundColor Yellow
Write-Host "  1. Upload $zipFileName to release location" -ForegroundColor Yellow
Write-Host "  2. Include checksums-v$Version.txt for verification" -ForegroundColor Yellow
Write-Host "  3. Share QUICK-START-v$Version.txt with users" -ForegroundColor Yellow
Write-Host ""

Write-Host "Testing:" -ForegroundColor Green
Write-Host "  1. Extract ZIP to test location" -ForegroundColor Green
Write-Host "  2. Run install.ps1" -ForegroundColor Green
Write-Host "  3. Verify installation completes successfully" -ForegroundColor Green
Write-Host ""

Write-Success "Build completed successfully!"
Write-Host ""
