# Define the target group
$groupPattern = '*-32752*'

# Search for rules that are NOT enabled but belong to the Public profile
$targetRules = Get-NetFirewallRule -Group $groupPattern -ErrorAction SilentlyContinue | 
               Where-Object { $_.Profile -match 'Public' -and $_.Enabled -eq 'False' }

if ($targetRules) {
    Write-Output "Detection: Found $($targetRules.Count) disabled rule(s) in group $groupPattern on Public profile."
    # Exit with 1 to signal that remediation is required
    Exit 1
} else {
    Write-Output "Detection: All rules are compliant or no rules found."
    # Exit with 0 to signal everything is fine
    Exit 0
}