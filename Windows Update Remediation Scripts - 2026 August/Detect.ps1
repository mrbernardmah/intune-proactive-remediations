# ==============================================================================
# Script: Detect-WindowsUpdateErrors.ps1
# Description: Detects recent Windows Update failure events in the System Log.
# Exit 1 = Issues found (Triggers Remediation)
# Exit 0 = Compliant (No Remediation needed)
# ==============================================================================

# Threshold Configurations
$maxEventLogDays   = 7     # Look back window in days
$maxEventLogEntries = 100   # Maximum events to query
$errorThreshold     = 5     # Number of errors required to trigger remediation

try {
    # Query System log for WindowsUpdateClient error/failure IDs
    $recentUpdateErrors = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        ID        = 16, 20, 24, 25, 31, 34, 35
        StartTime = (Get-Date).AddDays(-$maxEventLogDays)
    } -MaxEvents $maxEventLogEntries -ErrorAction SilentlyContinue

    # Ensure array syntax so single event returns count of 1 instead of $null
    $errorCount = if ($recentUpdateErrors) { @($recentUpdateErrors).Count } else { 0 }

    # Non-Compliant Condition: Errors exceed threshold
    if ($errorCount -gt $errorThreshold) {
        Write-Output "Non-Compliant: Found $errorCount Windows Update errors in the last $maxEventLogDays days (Threshold: $errorThreshold)."
        Exit 1
    }
    else {
        Write-Output "Compliant: Found $errorCount Windows Update errors in the last $maxEventLogDays days."
        Exit 0
    }
}
catch {
    Write-Output "Error querying event log: $_"
    Exit 1
}