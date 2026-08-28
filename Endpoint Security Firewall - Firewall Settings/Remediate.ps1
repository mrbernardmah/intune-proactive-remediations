function Set-WindowsFirewallConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    foreach ($profileName in $Configuration.Keys) {
        $targetSettings = $Configuration[$profileName]
        $currentProfile = Get-NetFirewallProfile -Name $profileName -ErrorAction Stop
        $paramsToUpdate = @{}

        foreach ($setting in $targetSettings.Keys) {
            $targetValue = $targetSettings[$setting]
            $currentValue = $currentProfile.$setting

            # Expand environment variables (%systemroot%) for accurate file path comparison
            if ($setting -eq 'LogFileName' -and $targetValue -is [string]) {
                $expandedTarget = [System.Environment]::ExpandEnvironmentVariables($targetValue)
                $expandedCurrent = [System.Environment]::ExpandEnvironmentVariables($currentValue)

                if ($expandedCurrent -ne $expandedTarget) {
                    $paramsToUpdate[$setting] = $targetValue
                }
                continue
            }

            # Convert boolean inputs to string to match NetSecurity GpoBoolean expectations
            if ($targetValue -is [bool]) {
                $targetValue = if ($targetValue) { 'True' } else { 'False' }
            }

            # String comparison handles Enums, Booleans, Strings, and Numbers cleanly
            if ($null -ne $currentValue -and "$currentValue" -ne "$targetValue") {
                $paramsToUpdate[$setting] = $targetValue
            }
        }

        # Apply updates via splatting if changes are required
        if ($paramsToUpdate.Count -gt 0) {
            Write-Verbose "Updating settings for profile [$profileName]: $($paramsToUpdate.Keys -join ', ')"
            Set-NetFirewallProfile -Name $profileName @paramsToUpdate -ErrorAction Stop
        }
    }
}

$TargetConfig = @{
    'Domain' = @{
        'Enabled'                                       = 'True'
        'DefaultInboundAction'                          = 'Block'
        'DefaultOutboundAction'                         = 'Allow'
        'LogFileName'                                   = '%systemroot%\system32\LogFiles\Firewall\domainfw.log'
        'LogMaxSizeKilobytes'                           = 16384
        'LogAllowed'                                    = 'True'
        'LogBlocked'                                    = 'True'
        'LogIgnored'                                    = 'False'
        'DisableInboundNotifications'                   = 'True'
        'DisableStealthMode'                            = 'False'
        'DisableStealthModeIpSecSecuredPacketExemption' = 'True'
        'Shielded'                                      = 'False'
    }
    'Private' = @{
        'Enabled'                                       = 'True'
        'DefaultInboundAction'                          = 'Block'
        'DefaultOutboundAction'                         = 'Allow'
        'LogFileName'                                   = '%systemroot%\system32\LogFiles\Firewall\privatefw.log'
        'LogMaxSizeKilobytes'                           = 16384
        'LogAllowed'                                    = 'True'
        'LogBlocked'                                    = 'True'
        'LogIgnored'                                    = 'False'
        'DisableInboundNotifications'                   = 'True'
        'DisableStealthMode'                            = 'False'
        'DisableStealthModeIpSecSecuredPacketExemption' = 'True'
        'Shielded'                                      = 'False'
    }
    'Public' = @{
        'Enabled'                                       = 'True'
        'DefaultInboundAction'                          = 'Block'
        'DefaultOutboundAction'                         = 'Allow'
        'LogFileName'                                   = '%systemroot%\system32\LogFiles\Firewall\publicfw.log'
        'LogMaxSizeKilobytes'                           = 16384
        'LogAllowed'                                    = 'True'
        'LogBlocked'                                    = 'True'
        'LogIgnored'                                    = 'False'
        'DisableInboundNotifications'                   = 'True'
        'DisableStealthMode'                            = 'False'
        'DisableStealthModeIpSecSecuredPacketExemption' = 'True'
        'Shielded'                                      = 'False'
        'DisableUnicastResponsesToMulticastBroadcast'   = 'False'
    }
}

try {
    Set-WindowsFirewallConfiguration -Configuration $TargetConfig
    Write-Output "[All good]. Remediation script is done running"
    exit 0
}
catch {
    Write-Output "[Not good]. Something went wrong when running the remediation script: $_"
    exit 1
}
