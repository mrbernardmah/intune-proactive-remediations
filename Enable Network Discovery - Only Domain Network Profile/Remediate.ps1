try {
    Write-Host "Enabling firewall rules for Group '*-32752*' on Domain profile..."
    
    # Perform the remediation
    Get-NetFirewallRule -Group '*-32752*' | 
        Where-Object { $_.Profile -match 'Domain' } | 
        Set-NetFirewallRule -Enabled 'True' -ErrorAction Stop
    
    Write-Host "Remediation successful."
    exit 0
}
catch {
    Write-Error "Failed to update firewall rules: $($_.Exception.Message)"
    exit 1
}