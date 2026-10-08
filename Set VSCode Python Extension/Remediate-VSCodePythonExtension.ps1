<#
.SYNOPSIS
    Intune Proactive Remediation - REMEDIATION (VS Code Python extension)
.NOTES
    Run as: LOGGED-ON USER (Run this script using the logged-on credentials = Yes)
    64-bit PowerShell: Yes
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
        Write-Output "VS Code not found. Skipping."
        exit 0
    }

    # stderr redirected so Node.js deprecation warnings aren't treated as failures
    & $code --install-extension $ExtensionId --force 2>$null | Out-Null

    $extensions = & $code --list-extensions 2>$null
    if ($extensions -contains $ExtensionId) {
        Write-Output "Installed $ExtensionId"
        exit 0
    }

    Write-Output "Extension install did not complete"
    exit 1
}
catch {
    Write-Output "Remediation error: $_"
    exit 1
}
