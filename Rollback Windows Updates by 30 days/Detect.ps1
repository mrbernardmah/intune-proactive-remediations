# =======================================================================================
# SCRIPT 1: DETECTION
# Purpose: Detect OS updates installed in the last 30 days. 
# =======================================================================================

$30DaysAgo = (Get-Date).AddDays(-30)
$UpdatesFound = $false

try {
    # Query the native Windows Update Agent API
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    $HistoryCount = $UpdateSearcher.GetTotalHistoryCount()

    if ($HistoryCount -gt 0) {
        $UpdateHistory = $UpdateSearcher.QueryHistory(0, $HistoryCount)

        # Filter out definitions, drivers, and failures
        $RecentUpdates = $UpdateHistory | Where-Object {
            $_.Date -ge $30DaysAgo -and 
            $_.ResultCode -eq 2 -and # 2 = Succeeded
            $_.Title -notmatch "Security Intelligence" -and 
            $_.Title -notmatch "Definition Update" -and
            $_.Title -notmatch "Driver" -and
            $_.Title -match "KB\d{6,7}"
        }

        if ($RecentUpdates) {
            Write-Host "Non-Compliant: Found $($RecentUpdates.Count) update(s) installed within 30 days."
            foreach ($Update in $RecentUpdates) {
                if ($Update.Title -match "KB\d{6,7}") {
                    Write-Host " -> Found: $($Matches[0]) ($($Update.Title))"
                }
            }
            $UpdatesFound = $true
        }
    }
}
catch {
    Write-Error "Detection failed: $_"
    exit 2 # Exit code 2 indicates a script/discovery error
}

if ($UpdatesFound) {
    exit 1 # Non-Compliant (Triggers Remediation)
} else {
    Write-Host "Compliant: No recent OS updates detected."
    exit 0 # Compliant
}