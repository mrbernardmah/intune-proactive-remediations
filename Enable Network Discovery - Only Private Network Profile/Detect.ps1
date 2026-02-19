# Check for rules in the group that are NOT enabled on the Private profile
$nonCompliantRules = Get-NetFirewallRule -Group '*-32752*' | 
    Where-Object { $_.Profile -match 'Private' -and $_.Enabled -eq 'False' }

if ($nonCompliantRules) {
    # If rules are found that need fixing, write to output to signal non-compliance
    Write-Output "Non-compliant: Found disabled firewall rules in group *-32752* on Private profile."
    Exit 1
} else {
    # If everything is already enabled, exit quietly
    Write-Output "Compliant."
    Exit 0
}