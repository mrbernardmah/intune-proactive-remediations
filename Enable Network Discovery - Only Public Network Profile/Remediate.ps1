try {
    $groupPattern = '*-32752*'

    # Apply the fix
    Get-NetFirewallRule -Group $groupPattern -ErrorAction Stop | 
        Where-Object { $_.Profile -match 'Public' } | 
        Set-NetFirewallRule -Enabled 'True' -ErrorAction Stop
    
    Write-Output "Remediation: Successfully enabled rules for group $groupPattern on Public profile."
    Exit 0
} catch {
    Write-Error "Remediation Failed: $($_.Exception.Message)"
    Exit 1
}