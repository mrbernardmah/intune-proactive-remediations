# Function to check if a firewall rule exists and is enabled
function Is-FirewallRuleEnabled {
    param (
        [string]$ruleName
    )
    $ruleStatus = netsh advfirewall firewall show rule name="$ruleName" | Select-String -Pattern "Enabled: Yes"
    return $ruleStatus -ne $null
}

# Function to check if a firewall rule group is enabled
function Is-FirewallRuleGroupEnabled {
    param (
        [string]$groupName
    )
    $rules = netsh advfirewall firewall show rule name=all | Select-String -Pattern $groupName
    return ($rules -match "Enabled: Yes")
}

# Define the individual firewall rules to check
$firewallRules = @(
    "Remote Desktop - Shadow (TCP-In)",
    "Remote Desktop - User Mode (TCP-In)",
    "Remote Desktop - User Mode (UDP-In)"
)

# Define the firewall rule groups to check
$firewallGroups = @(
    "File and Printer Sharing",
    "File and Printer Sharing (Restrictive)"
)

# Detect the status of each individual rule
foreach ($ruleName in $firewallRules) {
    $ruleEnabled = Is-FirewallRuleEnabled -ruleName $ruleName
    Write-Output "$ruleName Enabled: $ruleEnabled"
}

# Detect the status of each rule group
foreach ($groupName in $firewallGroups) {
    $groupEnabled = Is-FirewallRuleGroupEnabled -groupName $groupName
    Write-Output "$groupName Group Enabled: $groupEnabled"
}
