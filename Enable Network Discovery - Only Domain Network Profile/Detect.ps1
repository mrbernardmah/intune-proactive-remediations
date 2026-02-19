# Identify rules in the specific group on the Domain profile
$rules = Get-NetFirewallRule -Group '*-32752*' | Where-Object { $_.Profile -match 'Domain' }

if ($null -eq $rules) {
    Write-Host "No rules found matching the criteria. Nothing to enforce."
    exit 0
}

# Check if any of those rules are currently disabled
$disabledRules = $rules | Where-Object { $_.Enabled -ne 'True' }

if ($disabledRules) {
    Write-Host "Found $($disabledRules.Count) disabled firewall rules. Remediation required."
    exit 1 # Non-zero exit triggers the remediation script
} else {
    Write-Host "All rules are correctly enabled."
    exit 0
}