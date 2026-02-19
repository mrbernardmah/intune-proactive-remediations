# Search for rules matching the specific group pattern
$Rules = Get-NetFirewallRule -Group '*-32752*' -ErrorAction SilentlyContinue

if ($null -eq $Rules) {
    Write-Host "No rules found matching the group pattern."
    exit 1 # Trigger remediation if rules don't exist (optional, depending on your goal)
}

# Check if any of the rules are currently disabled
$DisabledRules = $Rules | Where-Object { $_.Enabled -eq 'False' }

if ($DisabledRules) {
    Write-Host "Found $($DisabledRules.Count) disabled firewall rules."
    exit 1 # Non-compliant, trigger Remediation
} else {
    Write-Host "All relevant firewall rules are enabled."
    exit 0 # Compliant, do nothing
}