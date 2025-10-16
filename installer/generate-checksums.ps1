<#
.SYNOPSIS
    Generate SHA256 checksums for FreshBooks MCP release artifacts
.DESCRIPTION
    Scans the releases\latest\ directory for release files, generates SHA256 checksums,
    and outputs both human-readable and machine-readable formats with metadata.
.PARAMETER ReleasesPath
    Path to the releases directory (defaults to ..\releases\latest)
.PARAMETER Verify
    Verify existing checksums instead of generating new ones
.PARAMETER Recursive
    Recursively scan subdirectories for artifacts
.EXAMPLE
    .\generate-checksums.ps1
.EXAMPLE
    .\generate-checksums.ps1 -Verify
.EXAMPLE
    .\generate-checksums.ps1 -ReleasesPath "C:\releases\latest" -Recursive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ReleasesPath = "..\releases\latest",

    [Parameter(Mandatory=$false)]
    [switch]$Verify,

    [Parameter(Mandatory=$false)]
    [switch]$Recursive
)

# Configuration
$ErrorActionPreference = "Stop"
$Script:TotalFiles = 0
$Script:SuccessCount = 0
$Script:FailureCount = 0
$Script:VerificationResults = @()

# ANSI color codes for output
$Script:Colors = @{
    Reset   = "`e[0m"
    Red     = "`e[91m"
    Green   = "`e[92m"
    Yellow  = "`e[93m"
    Blue    = "`e[94m"
    Magenta = "`e[95m"
    Cyan    = "`e[96m"
    White   = "`e[97m"
    Bold    = "`e[1m"
}



function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$NoNewline
    )

    $colorCode = $Script:Colors[$Color]
    $resetCode = $Script:Colors.Reset

    if ($NoNewline) {
        Write-Host "$colorCode$Message$resetCode" -NoNewline
    } else {
        Write-Host "$colorCode$Message$resetCode"
    }
}

function Write-Header {
    param([string]$Title)

    $separator = "=" * 80
    Write-ColorOutput "`n$separator" -Color "Cyan"
    Write-ColorOutput "  $Title" -Color "Cyan"
    Write-ColorOutput "$separator`n" -Color "Cyan"
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "[✓] $Message" -Color "Green"
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-ColorOutput "[✗] $Message" -Color "Red"
}

function Write-WarningMessage {
    param([string]$Message)
    Write-ColorOutput "[!] $Message" -Color "Yellow"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "[i] $Message" -Color "Blue"
}

function Format-FileSize {
    param([long]$Size)

    if ($Size -gt 1GB) {
        return "{0:N2} GB" -f ($Size / 1GB)
    } elseif ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "$Size bytes"
    }
}

function Get-FileMetadata {
    param([System.IO.FileInfo]$File)

    return [PSCustomObject]@{
        Name = $File.Name
        Path = $File.FullName
        Size = $File.Length
        SizeFormatted = Format-FileSize -Size $File.Length
        Created = $File.CreationTime
        Modified = $File.LastWriteTime
        Extension = $File.Extension
    }
}

function Get-FileChecksum {
    param(
        [System.IO.FileInfo]$File,
        [string]$Algorithm = "SHA256"
    )

    try {
        Write-Info "Computing $Algorithm hash for: $($File.Name)"

        # Use streaming for large files to avoid memory issues
        $hash = Get-FileHash -Path $File.FullName -Algorithm $Algorithm -ErrorAction Stop

        return [PSCustomObject]@{
            Success = $true
            Hash = $hash.Hash.ToLower()
            Algorithm = $Algorithm
            File = $File
            Error = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Hash = $null
            Algorithm = $Algorithm
            File = $File
            Error = $_.Exception.Message
        }
    }
}

function Get-ReleaseArtifacts {
    param(
        [string]$Path,
        [bool]$Recursive
    )

    # Exclude checksum files and README from artifact list
    $excludePatterns = @(
        "checksums.txt",
        "checksums.json",
        "README.md",
        "*.md",
        ".gitkeep"
    )

    $searchParams = @{
        Path = $Path
        File = $true
        Recurse = $Recursive
    }

    $allFiles = Get-ChildItem @searchParams

    # Filter out excluded files
    $artifacts = $allFiles | Where-Object {
        $fileName = $_.Name
        $shouldInclude = $true

        foreach ($pattern in $excludePatterns) {
            if ($fileName -like $pattern) {
                $shouldInclude = $false
                break
            }
        }

        $shouldInclude
    }

    return $artifacts
}





function New-ChecksumFiles {
    param(
        [string]$TargetPath,
        [bool]$Recursive
    )

    Write-Header "FreshBooks MCP - Release Artifact Checksum Generator"

    # Resolve and validate path
    $resolvedPath = Resolve-Path -Path $TargetPath -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        throw "Path not found: $TargetPath"
    }

    Write-Info "Scanning directory: $resolvedPath"
    Write-Info "Recursive mode: $Recursive"

    # Get all release artifacts
    $artifacts = Get-ReleaseArtifacts -Path $resolvedPath -Recursive $Recursive

    if ($artifacts.Count -eq 0) {
        Write-WarningMessage "No release artifacts found in $resolvedPath"
        return
    }

    Write-Info "Found $($artifacts.Count) artifact(s)"
    Write-Host ""

    # Generate checksums
    $checksumData = @()
    $Script:TotalFiles = $artifacts.Count

    foreach ($artifact in $artifacts) {
        $metadata = Get-FileMetadata -File $artifact
        $checksumResult = Get-FileChecksum -File $artifact -Algorithm "SHA256"

        if ($checksumResult.Success) {
            $Script:SuccessCount++

            $checksumEntry = [PSCustomObject]@{
                fileName = $metadata.Name
                filePath = $metadata.Path
                hash = $checksumResult.Hash
                algorithm = "SHA256"
                size = $metadata.Size
                sizeFormatted = $metadata.SizeFormatted
                created = $metadata.Created.ToString("yyyy-MM-ddTHH:mm:sszzz")
                modified = $metadata.Modified.ToString("yyyy-MM-ddTHH:mm:sszzz")
                extension = $metadata.Extension
                generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
            }

            $checksumData += $checksumEntry
            Write-Success "Generated checksum for $($metadata.Name) ($($metadata.SizeFormatted))"
        }
        else {
            $Script:FailureCount++
            Write-ErrorMessage "Failed to generate checksum for $($metadata.Name): $($checksumResult.Error)"
        }
    }

    if ($checksumData.Count -eq 0) {
        Write-ErrorMessage "No checksums generated"
        return
    }

    # Output human-readable format
    Write-Host "`n"
    Write-Info "Writing human-readable checksums to checksums.txt"
    $textOutputPath = Join-Path -Path $resolvedPath -ChildPath "checksums.txt"

    $textContent = @()
    $textContent += "# FreshBooks MCP - Release Artifact Checksums"
    $textContent += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $textContent += "# Algorithm: SHA256"
    $textContent += "#"
    $textContent += ""

    foreach ($entry in $checksumData) {
        # Format: hash  filename (size)
        $textContent += "$($entry.hash)  $($entry.fileName)"
        $textContent += "#   Size: $($entry.sizeFormatted)"
        $textContent += "#   Modified: $($entry.modified)"
        $textContent += ""
    }

    $textContent += "# Verification Instructions:"
    $textContent += "# PowerShell: Get-FileHash -Path <filename> -Algorithm SHA256"
    $textContent += "# Linux/Mac: sha256sum -c checksums.txt"

    $textContent | Out-File -FilePath $textOutputPath -Encoding utf8 -Force
    Write-Success "Created: $textOutputPath"

    # Output machine-readable JSON format
    Write-Info "Writing machine-readable checksums to checksums.json"
    $jsonOutputPath = Join-Path -Path $resolvedPath -ChildPath "checksums.json"

    $jsonOutput = [PSCustomObject]@{
        version = "1.0.0"
        generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
        generator = "FreshBooks MCP Checksum Generator"
        algorithm = "SHA256"
        totalFiles = $checksumData.Count
        artifacts = $checksumData
    }

    $jsonOutput | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonOutputPath -Encoding utf8 -Force
    Write-Success "Created: $jsonOutputPath"

    # Display summary
    Write-Host "`n"
    Write-Header "Summary"
    Write-ColorOutput "Total artifacts: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:TotalFiles" -Color "Cyan"
    Write-ColorOutput "Successful: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:SuccessCount" -Color "Green"
    Write-ColorOutput "Failed: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:FailureCount" -Color $(if ($Script:FailureCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""
}





function Test-Checksums {
    param([string]$TargetPath)

    Write-Header "FreshBooks MCP - Release Artifact Checksum Verification"

    # Resolve path
    $resolvedPath = Resolve-Path -Path $TargetPath -ErrorAction SilentlyContinue
    if (-not $resolvedPath) {
        throw "Path not found: $TargetPath"
    }

    # Check for checksums.json
    $jsonPath = Join-Path -Path $resolvedPath -ChildPath "checksums.json"
    if (-not (Test-Path -Path $jsonPath)) {
        Write-ErrorMessage "Checksums file not found: $jsonPath"
        Write-Info "Run without -Verify flag to generate checksums first"
        return
    }

    Write-Info "Loading checksums from: $jsonPath"

    try {
        $checksumData = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-ErrorMessage "Failed to parse checksums.json: $($_.Exception.Message)"
        return
    }

    Write-Info "Verifying $($checksumData.artifacts.Count) artifact(s)"
    Write-Host ""

    $Script:TotalFiles = $checksumData.artifacts.Count
    $Script:SuccessCount = 0
    $Script:FailureCount = 0

    foreach ($entry in $checksumData.artifacts) {
        $fileName = $entry.fileName
        $expectedHash = $entry.hash
        $filePath = Join-Path -Path $resolvedPath -ChildPath $fileName

        Write-Info "Verifying: $fileName"

        if (-not (Test-Path -Path $filePath)) {
            $Script:FailureCount++
            Write-ErrorMessage "File not found: $fileName"

            $Script:VerificationResults += [PSCustomObject]@{
                File = $fileName
                Status = "MISSING"
                Expected = $expectedHash
                Actual = $null
                Match = $false
            }
            continue
        }

        # Get current file hash
        $fileInfo = Get-Item -Path $filePath
        $currentResult = Get-FileChecksum -File $fileInfo -Algorithm "SHA256"

        if (-not $currentResult.Success) {
            $Script:FailureCount++
            Write-ErrorMessage "Failed to compute hash: $($currentResult.Error)"

            $Script:VerificationResults += [PSCustomObject]@{
                File = $fileName
                Status = "ERROR"
                Expected = $expectedHash
                Actual = $null
                Match = $false
                Error = $currentResult.Error
            }
            continue
        }

        $currentHash = $currentResult.Hash
        $matches = ($currentHash -eq $expectedHash)

        if ($matches) {
            $Script:SuccessCount++
            Write-Success "VERIFIED: $fileName"
            Write-ColorOutput "  Expected: $expectedHash" -Color "White"
            Write-ColorOutput "  Current:  $currentHash" -Color "Green"

            $Script:VerificationResults += [PSCustomObject]@{
                File = $fileName
                Status = "VERIFIED"
                Expected = $expectedHash
                Actual = $currentHash
                Match = $true
            }
        }
        else {
            $Script:FailureCount++
            Write-ErrorMessage "MISMATCH: $fileName"
            Write-ColorOutput "  Expected: $expectedHash" -Color "Yellow"
            Write-ColorOutput "  Current:  $currentHash" -Color "Red"

            $Script:VerificationResults += [PSCustomObject]@{
                File = $fileName
                Status = "MISMATCH"
                Expected = $expectedHash
                Actual = $currentHash
                Match = $false
            }
        }

        Write-Host ""
    }

    # Display summary
    Write-Header "Verification Summary"
    Write-ColorOutput "Total files checked: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:TotalFiles" -Color "Cyan"
    Write-ColorOutput "Verified: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:SuccessCount" -Color "Green"
    Write-ColorOutput "Failed: " -Color "White" -NoNewline
    Write-ColorOutput "$Script:FailureCount" -Color $(if ($Script:FailureCount -gt 0) { "Red" } else { "Green" })

    if ($Script:FailureCount -gt 0) {
        Write-Host ""
        Write-WarningMessage "INTEGRITY CHECK FAILED!"
        Write-WarningMessage "One or more artifacts have been modified or are missing."
        exit 1
    }
    else {
        Write-Host ""
        Write-Success "ALL ARTIFACTS VERIFIED SUCCESSFULLY!"
        exit 0
    }
}





function Invoke-Main {
    param(
        [string]$RelPath,
        [bool]$DoVerify,
        [bool]$IsRecursive
    )

    try {
        # Check PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            throw "This script requires PowerShell 5.0 or higher"
        }

        # Execute based on mode
        if ($DoVerify) {
            Test-Checksums -TargetPath $RelPath
        }
        else {
            New-ChecksumFiles -TargetPath $RelPath -Recursive $IsRecursive
        }
    }
    catch {
        Write-Host "`n"
        Write-Host "[✗] FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        exit 1
    }
}

# Execute main function
Invoke-Main -RelPath $ReleasesPath -DoVerify $Verify -IsRecursive $Recursive


