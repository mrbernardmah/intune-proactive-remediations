<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects system-context (all-users) Python installs at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    python.org installers register:
      - a bundle entry          "Python 3.12.2 (64-bit)"                    DisplayVersion 3.12.2150.0
      - hidden component MSIs   "Python 3.12.2 Core Interpreter (64-bit)"   etc.
    The version is read from the DisplayName ("Python X.Y.Z ..."), because
    DisplayVersion encodes the release level (3.12.2 -> 3.12.2150.0).

    "Python Launcher" (py.exe) and "Python Install Manager" are shared and NOT targeted.

    Exit 1 = targeted Python found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove (X.Y.Z). Must match the remediation script.
$TargetVersions = @('3.12.13', '3.12.2', '3.14.7', '3.5.1')

$ErrorActionPreference = 'SilentlyContinue'

function Get-PythonVersionFromName([string]$Name) {
    if ($Name -match '^Python (\d+\.\d+\.\d+)\b' -and $Name -notmatch '^Python (Launcher|Install Manager)') {
        return $Matches[1]
    }
    return $null
}

$found = @()

foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem -Path $root | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        $v = Get-PythonVersionFromName $p.DisplayName
        if ($v -and $TargetVersions -contains $v) {
            $found += $p.DisplayName
        }
    }
}

# PEP 514 registration (HKLM\SOFTWARE\Python\PythonCore\<tag>\Version)
foreach ($pc in @('HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
    Get-ChildItem -Path $pc | ForEach-Object {
        $ver = (Get-ItemProperty -Path $_.PSPath).Version
        $exe = (Get-ItemProperty -Path (Join-Path $_.PSPath 'InstallPath')).ExecutablePath
        if ($ver -and $TargetVersions -contains $ver -and $exe -and (Test-Path $exe)) {
            $found += "PythonCore $($_.PSChildName) [$ver] $exe"
        }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted Python version(s) not found"
exit 0