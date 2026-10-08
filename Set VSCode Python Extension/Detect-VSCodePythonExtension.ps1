<#
.SYNOPSIS
    Intune Proactive Remediation - DETECTION (VS Code Python extension)
.NOTES
    Run as: LOGGED-ON USER (Run this script using the logged-on credentials = Yes)
    64-bit PowerShell: Yes
    Exit 0 = compliant (or VS Code not installed), Exit 1 = extension missing
#>

$ExtensionId = "ms-python.python"

function Get-VSCodeCli {
    $paths = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

try {
    $code = Get-VSCodeCli
    if (-not $code) {
        Write-Output "COMPLIANT: VS Code not installed, nothing to do"
        exit 0
    }

    $extensions = & $code --list-extensions 2>$null
    if ($extensions -contains $ExtensionId) {
        Write-Output "COMPLIANT: $ExtensionId installed"
        exit 0
    }

    Write-Output "NON-COMPLIANT: $ExtensionId not installed"
    exit 1
}
catch {
    Write-Output "NON-COMPLIANT: Detection error: $_"
    exit 1
}
