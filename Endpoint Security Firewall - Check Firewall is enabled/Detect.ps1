# Get the active firewall profiles and check if any profile is disabled
$DisabledProfiles = Get-NetFirewallProfile -PolicyStore ActiveStore | Where-Object { $_.Enabled -eq 'False' }

if ($DisabledProfiles) {
    # One or more firewall profiles are turned off. Trigger remediation.
    Write-Output "Non-Compliant: The following firewall profiles are disabled: $($DisabledProfiles.Name)"
    Exit 1
} else {
    # All firewall profiles (Domain, Private, Public) are active and running.
    Write-Output "Compliant: Windows Firewall is enabled for all network profiles."
    Exit 0
}