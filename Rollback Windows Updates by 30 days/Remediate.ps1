# =======================================================================================
# SCRIPT 2: REMEDIATION
# Purpose: Roll back OS updates installed within the last 30 days and reboot.
# =======================================================================================

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Remediation must be run with Administrator privileges."
    exit 1
}

$30DaysAgo = (Get-Date).AddDays(-30)

try {
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    $HistoryCount = $UpdateSearcher.GetTotalHistoryCount()

    if ($HistoryCount -eq 0) {
        Write-Host "No update history found to remediate."
        exit 0
    }

    $UpdateHistory = $UpdateSearcher.QueryHistory(0, $HistoryCount)
    $RecentUpdates = $UpdateHistory | Where-Object {
        $_.Date -ge $30DaysAgo -and 
        $_.ResultCode -eq 2 -and 
        $_.Title -notmatch "Security Intelligence" -and 
        $_.Title -notmatch "Definition Update" -and
        $_.Title -notmatch "Driver"
    }

    if (-not $RecentUpdates) {
        Write-Host "No targets available for rollback."
        exit 0
    }

    foreach ($Update in $RecentUpdates) {
        if ($Update.Title -match "KB\d{6,7}") {
            $KBNumber = $Matches[0]
            Write-Host "Processing rollback for $KBNumber..."

            # Method A: DISM (Highly recommended for Windows 10/11 Cumulative Updates)
            $PackageName = (Get-WindowsPackage -Online | Where-Object { $_.PackageName -like "*$KBNumber*" }).PackageName

            if ($PackageName) {
                Write-Host "Removing package via DISM: $PackageName"
                Remove-WindowsPackage -Online -PackageName $PackageName -NoRestart -ErrorAction SilentlyContinue
            } 
            else {
                # Method B: Fallback to WUSA for individual patches/older frameworks
                Write-Host "Package not found in DISM. Attempting WUSA fallback for $KBNumber..."
                $KbClean = $KBNumber.Replace('KB','')
                Start-Process "wusa.exe" -ArgumentList "/uninstall /kb:$KbClean /quiet /norestart" -NoNewWindow -Wait
            }
        }
    }

    # Post-Remediation Reboot
    Write-Host "Remediation complete. Initiating forced reboot in 60 seconds..."
    Start-Sleep -Seconds 60
    Restart-Computer -Force
}
catch {
    Write-Error "Remediation encountered an error: $_"
    exit 1
}