<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Wireshark (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Exit 1 = targeted Wireshark found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY Wireshark version. Must match the remediation script.
$TargetVersions = @('4.6.6')

$ErrorActionPreference = 'SilentlyContinue'

function Test-TargetVersion([string]$Version) {
    if (-not $Version) { return $false }
    if ($TargetVersions.Count -eq 0) { return $true }
    foreach ($t in $TargetVersions) {
        if ($Version -eq $t -or $Version -like "$t.*") { return $true }
    }
    return $false
}

$found = @()

# Registry (NSIS .exe and MSI installs)
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($root in $uninstallRoots) {
    Get-ChildItem -Path $root | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        if ($p.DisplayName -like 'Wireshark*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

# File check (catches orphaned installs with no uninstall entry)
foreach ($exe in @("$env:ProgramFiles\Wireshark\Wireshark.exe", "${env:ProgramFiles(x86)}\Wireshark\Wireshark.exe")) {
    if (Test-Path $exe) {
        $v = (Get-Item $exe).VersionInfo.ProductVersion
        if (Test-TargetVersion $v) { $found += "$exe [$v]" }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted Wireshark version not found"
exit 0