# Remediate-FirewallGroups.ps1
# Enables the specified firewall rule groups using netsh

$firewallGroups = @(
    "File and Printer Sharing",
    "File and Printer Sharing (Restrictive)"
)

foreach ($group in $firewallGroups) {
    Write-Output "Enabling firewall rule group: $group"
    netsh advfirewall firewall set rule group="$group" new enable=Yes
}
