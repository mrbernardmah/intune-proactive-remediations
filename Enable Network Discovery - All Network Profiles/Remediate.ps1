try {
    # Attempt to enable the rules
    Set-NetFirewallRule -Group '*-32752*' -Enabled 'True' -ErrorAction Stop
    Write-Host "Successfully enabled firewall rules for group: *-32752*"
    exit 0
}
catch {
    Write-Error "Failed to enable firewall rules: $($_.Exception.Message)"
    exit 1
}