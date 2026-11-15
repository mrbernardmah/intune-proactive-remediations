<#
.SYNOPSIS
    Intune Remediation - DETECTION (REVERT)
    Checks the device is back to its original state: built-in Administrator (RID 500)
    enabled and the biadm account removed.

.NOTES
    Run as: System | 64-bit PowerShell: Yes
    Exit 0 = reverted, Exit 1 = run remediation
#>

$AccountName = 'biadm'

try {
    $issues = @()

    $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' }
    if ($builtIn -and -not $builtIn.Enabled) {
        $issues += "Built-in Administrator ($($builtIn.Name)) is disabled"
    }

    if (Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue) {
        $issues += "$AccountName still exists"
    }

    if ($issues.Count -gt 0) {
        Write-Output ("Not reverted: " + ($issues -join '; '))
        exit 1
    }

    Write-Output "Reverted: built-in Administrator enabled and $AccountName removed"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}