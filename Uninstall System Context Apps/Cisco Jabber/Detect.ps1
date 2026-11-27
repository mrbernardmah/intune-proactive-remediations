<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Cisco Jabber (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Exit 1 = targeted Cisco Jabber found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY version. Must match the remediation script.
$TargetVersions = @('12.9.1.53980')

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

foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem -Path $root | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        if ($p.DisplayName -like 'Cisco Jabber*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

# File check (catches installs with no uninstall entry)
foreach ($exe in @("${env:ProgramFiles(x86)}\Cisco Systems\Cisco Jabber\CiscoJabber.exe",
                   "$env:ProgramFiles\Cisco Systems\Cisco Jabber\CiscoJabber.exe")) {
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

Write-Output "Compliant: targeted Cisco Jabber version not found"
exit 0