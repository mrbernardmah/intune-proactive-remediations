<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects the uninstall registry key
    HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{421B3A26-5838-4EBA-AA36-C5A12A069D9E}

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes   (required - the path names WOW6432Node explicitly)

    Exit 1 = key exists -> remediation runs
    Exit 0 = compliant
#>

$KeyPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{421B3A26-5838-4EBA-AA36-C5A12A069D9E}'

if (Test-Path -LiteralPath $KeyPath) {
    $p = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    Write-Output "Non-compliant: key present - $($p.DisplayName) [$($p.DisplayVersion)]"
    exit 1
}

Write-Output "Compliant: key not present"
exit 0