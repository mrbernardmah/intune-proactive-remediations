<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Rapid7 Insight Agent (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Registry-based only: the agent keeps older versioned folders under
    components\insight_agent\ after it self-updates, so a folder check would
    give false positives.

    Exit 1 = targeted Insight Agent found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY version. Must match the remediation script.
$TargetVersions = @('4.0.7.26')

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
        if ($p.DisplayName -like 'Rapid7 Insight Agent*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted Rapid7 Insight Agent version not found"
exit 0