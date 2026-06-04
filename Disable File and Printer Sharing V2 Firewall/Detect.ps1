# Detect-FirewallGroups-Outbound.ps1
$firewallGroups = @(
    "File and Printer Sharing",
    "File and Printer Sharing (Restrictive)"
)

$compliant = $true

foreach ($group in $firewallGroups) {
    $enabledOutbound = Get-NetFirewallRule -DisplayGroup $group -Enabled True -Direction Outbound -ErrorAction SilentlyContinue 

    if ($enabledOutbound) {
        Write-Host "Non-Compliant: '$group' has outbound rules enabled."
        $compliant = $false
    }
}

if ($compliant) {
    Write-Host "Compliant: No outbound sharing rules enabled."
    exit 0
} else {
    exit 1
}