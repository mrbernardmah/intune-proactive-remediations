<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Google Chrome installed in SYSTEM context (Program Files / HKLM).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Exit 1 = targeted system-context Chrome found -> remediation runs
    Exit 0 = compliant

    Version is read from chrome.exe / version folders, not the MSI DisplayVersion
    (Chrome Enterprise MSI registers an encoded version that doesn't match Chrome's).
#>

# Versions to remove. Empty = ANY system-context Chrome version.
# Must match the remediation script.
$TargetVersions = @('149.0.7827.102')

$ErrorActionPreference = 'SilentlyContinue'

$appDirs = @(
    "$env:ProgramFiles\Google\Chrome\Application",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application"
) | Select-Object -Unique

$versions = @()
foreach ($dir in $appDirs) {
    if (-not (Test-Path $dir)) { continue }
    $exe = Join-Path $dir 'chrome.exe'
    if (Test-Path $exe) {
        $v = (Get-Item $exe).VersionInfo.ProductVersion
        if ($v) { $versions += $v }
    }
    $versions += Get-ChildItem -Path $dir -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Select-Object -ExpandProperty Name
}

# Registry (non-MSI installer writes DisplayVersion = real Chrome version)
foreach ($key in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome')) {
    if (Test-Path $key) {
        $v = (Get-ItemProperty $key).DisplayVersion
        if ($v) { $versions += $v }
    }
}

$versions = $versions | Sort-Object -Unique

if (-not $versions) {
    Write-Output "Compliant: no system-context Chrome found"
    exit 0
}

if ($TargetVersions.Count -gt 0) {
    $matched = $versions | Where-Object { $TargetVersions -contains $_ }
    if (-not $matched) {
        Write-Output "Compliant: system Chrome present ($($versions -join ', ')) but not a targeted version"
        exit 0
    }
    $versions = $matched
}

Write-Output "Non-compliant: system-context Chrome found - version(s): $($versions -join ', ')"
exit 1