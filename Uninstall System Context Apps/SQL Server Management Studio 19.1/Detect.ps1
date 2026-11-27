<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Microsoft SQL Server Management Studio (system context) by its
    display name in Apps & Features.

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Matches on DisplayName (wildcards allowed), because SSMS 19.x versions all
    install into the same "Management Studio 19" folder, so the folder alone
    can't tell 19.1 apart from 19.3.

    Exit 1 = targeted SSMS found -> remediation runs
    Exit 0 = compliant
#>

# DisplayNames to remove. Must match the remediation script.
# e.g. @('Microsoft SQL Server Management Studio - 19*') for every 19.x release
$TargetDisplayNames = @('Microsoft SQL Server Management Studio - 19.1')

$ErrorActionPreference = 'SilentlyContinue'

$found = @()
foreach ($root in @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
    Get-ChildItem -Path $root | ForEach-Object {
        $p = Get-ItemProperty -Path $_.PSPath
        if (-not $p.DisplayName -or $p.SystemComponent -eq 1) { return }
        foreach ($t in $TargetDisplayNames) {
            if ($p.DisplayName -like $t) {
                $found += "$($p.DisplayName) [$($p.DisplayVersion)]"
                break
            }
        }
    }
}

$found = $found | Sort-Object -Unique

if ($found) {
    Write-Output "Non-compliant: $($found -join '; ')"
    exit 1
}

Write-Output "Compliant: targeted SSMS not found"
exit 0