try {
    # Attempt to enable the specific rules
    Get-NetFirewallRule -Group '*-32752*' | 
        Where-Object { $_.Profile -match 'Private' } | 
        Set-NetFirewallRule -Enabled 'True' -ErrorAction Stop
    
    Write-Output "Remediation successful: Firewall rules enabled."
} catch {
    Write-Error "Failed to remediate firewall rules: $($_.Exception.Message)"
    Exit 1
}