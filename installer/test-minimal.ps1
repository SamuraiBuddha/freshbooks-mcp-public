[CmdletBinding()]
param(
    [string]$Path = "..\releases\latest"
)

function Test-MyFunction {
    Write-Host "Function works! Path: $Path"
}

Test-MyFunction
