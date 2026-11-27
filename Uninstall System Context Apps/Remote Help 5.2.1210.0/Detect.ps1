<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Microsoft Remote Help (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Matches the "Remote help" entry in Apps & Features by DisplayVersion.
    (RemoteHelp.exe has its own file version that differs from the app version,
    so the exe is not used for version matching.)

    Exit 1 = targeted Remote Help found -> remediation runs
    Exit 0 = compliant
#>

# Versions to remove. Empty = ANY version. Must match the remediation script.
$TargetVersions = @('5.2.1210.0')

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
        if ($p.DisplayName -like 'Remote help*' -and (Test-TargetVersion $p.DisplayVersion)) {
            $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
        }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted Remote Help version not found"
exit 0