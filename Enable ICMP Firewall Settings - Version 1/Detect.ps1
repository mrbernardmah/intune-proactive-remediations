# Detect-FirewallGroups.ps1
# Checks if the specified firewall rule groups are enabled

function Is-FirewallRuleGroupEnabled {
    param (
        [string]$groupName
    )
    $rules = netsh advfirewall firewall show rule name=all | Select-String -Pattern $groupName
    return ($rules -match "Enabled: Yes")
}

$firewallGroups = @(
    "File and Printer Sharing",
    "File and Printer Sharing (Restrictive)"
)

foreach ($group in $firewallGroups) {
    if (Is-FirewallRuleGroupEnabled -groupName $group) {
        Write-Output "'$group' firewall rule group is enabled."
    } else {
        Write-Output "'$group' firewall rule group is NOT enabled."
    }
}
