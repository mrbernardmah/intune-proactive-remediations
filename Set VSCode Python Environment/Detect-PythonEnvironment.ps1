<#
.SYNOPSIS
    Intune Proactive Remediation - DETECTION (Python + required pip packages)
.NOTES
    Run as: SYSTEM (Run this script using the logged-on credentials = No)
    64-bit PowerShell: Yes
    Exit 0 = compliant, Exit 1 = non-compliant (triggers remediation)
#>

$RequiredPackages = @(
    "azure-identity",
    "azure-mgmt-resource",
    "msal",
    "msgraph-sdk",
    "python-dotenv",
    "pandas",
    "openpyxl",
    "requests"
)

function Get-PythonExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { return $path }
    }

    # Fallback to PATH, ignoring Windows Store aliases
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*WindowsApps*") {
        return $cmd.Source
    }
    return $null
}

function Normalize-PackageName([string]$Name) {
    # PEP 503 normalisation: case-insensitive, treat - _ . as equivalent
    return ($Name.ToLower() -replace '[-_.]+', '-')
}

try {
    $pythonCmd = Get-PythonExecutable
    if (-not $pythonCmd) {
        Write-Output "NON-COMPLIANT: Python 3.12 not found"
        exit 1
    }

    $installedList = & $pythonCmd -m pip list --format=freeze 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "NON-COMPLIANT: pip is unavailable for $pythonCmd"
        exit 1
    }

    $installed = $installedList | ForEach-Object { Normalize-PackageName (($_ -split '==')[0]) }
    $missing = $RequiredPackages | Where-Object { $installed -notcontains (Normalize-PackageName $_) }

    if ($missing) {
        Write-Output "NON-COMPLIANT: Missing packages: $($missing -join ', ')"
        exit 1
    }

    Write-Output "COMPLIANT: Python at $pythonCmd with all required packages"
    exit 0
}
catch {
    Write-Output "NON-COMPLIANT: Detection error: $_"
    exit 1
}
