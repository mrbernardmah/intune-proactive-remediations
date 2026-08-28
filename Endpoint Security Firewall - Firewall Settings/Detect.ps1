$TargetProfiles = @('Domain', 'Private', 'Public')

$DesiredConfig = @{
    Enabled               = 'True'
    DefaultInboundAction  = 'NotConfigured'
    DefaultOutboundAction = 'NotConfigured'
    LogFileName           = '%systemroot%\system32\LogFiles\Firewall\pfirewall.log'
    LogMaxSizeKilobytes   = 4096
    LogAllowed            = 'False'
    LogBlocked            = 'False'
    LogIgnored            = 'NotConfigured'
}

$NonCompliant = $false

foreach ($ProfileName in $TargetProfiles) {
    $Current = Get-NetFirewallProfile -Name $ProfileName

    foreach ($Key in $DesiredConfig.Keys) {
        $CurrentValue = [string]$Current.$Key
        $DesiredValue = [string]$DesiredConfig[$Key]

        if ($CurrentValue -ne $DesiredValue) {
            Write-Warning "Mismatch found on $ProfileName profile for parameter '$Key'. Current: '$CurrentValue' | Expected: '$DesiredValue'"
            $NonCompliant = $true
        }
    }
}

if ($NonCompliant) {
    Write-Output "Firewall settings do not match target baseline. Triggering remediation."
    exit 1
} else {
    Write-Output "Firewall settings are fully compliant."
    exit 0
}
