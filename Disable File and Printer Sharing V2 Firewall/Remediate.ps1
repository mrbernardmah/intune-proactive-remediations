# Remediate-FirewallGroups-Outbound.ps1
$firewallGroups = @(
    "File and Printer Sharing",
    "File and Printer Sharing (Restrictive)"
)

foreach ($group in $firewallGroups) {
    Write-Host "Processing group: $group"
    Disable-NetFirewallRule -DisplayGroup $group -Direction Outbound -ErrorAction SilentlyContinue
}

# Final Verification to ensure 'Recurred' status is avoided
$remaining = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing*" -Enabled True -Direction Outbound -ErrorAction SilentlyContinue

if ($null -eq $remaining) {
    Write-Host "Remediation Successful: All outbound rules disabled."
    exit 0
} else {
    Write-Error "Remediation Failed: Some rules could not be disabled."
    exit 1
}