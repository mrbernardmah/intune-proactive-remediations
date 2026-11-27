<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects HP Client Management Script Library (CMSL, system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Versions are compared numerically, so 1.7.0 = 1.7.0.0.

    Exit 1 = targeted HP CMSL found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY version. Must match the remediation script.
$TargetVersions = @('1.7.0.0', '1.8.1.0')

$ErrorActionPreference = 'SilentlyContinue'

function ConvertTo-Version4([string]$v) {
    if (-not $v) { return $null }
    $parts = @($v.Trim() -split '[^\d]+' | Where-Object { $_ -ne '' } | Select-Object -First 4)
    while ($parts.Count -lt 4) { $parts += '0' }
    try { [version]($parts -join '.') } catch { $null }
}

function Test-TargetVersion([string]$Version) {
    $v = ConvertTo-Version4 $Version
    if (-not $v) { return $false }
    if ($TargetVersions.Count -eq 0) { return $true }
    foreach ($t in $TargetVersions) { if ($v -eq (ConvertTo-Version4 $t)) { return $true } }
    return $false
}

$found = @()
foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem -Path $root | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        if ($p.DisplayName -like 'HP Client Management Script Library*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted HP CMSL version not found"
exit 0