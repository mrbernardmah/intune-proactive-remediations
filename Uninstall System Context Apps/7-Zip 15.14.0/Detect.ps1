<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects 7-Zip (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Matches both install types:
      MSI : "7-Zip 15.14 (x64 edition)"  DisplayVersion 15.14.00.0
      EXE : "7-Zip 15.14 (x64)"          DisplayVersion 15.14

    Exit 1 = targeted 7-Zip found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY 7-Zip version. Must match the remediation script.
$TargetVersions = @('15.14')

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
        if ($p.DisplayName -like '7-Zip*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

# File check (catches orphaned installs with no uninstall entry)
foreach ($exe in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
    if (Test-Path $exe) {
        $v = (Get-Item $exe).VersionInfo.ProductVersion
        if (Test-TargetVersion ($v -replace '\s', '')) { $found += "$exe [$v]" }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted 7-Zip version not found"
exit 0