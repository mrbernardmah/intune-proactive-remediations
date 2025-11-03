# Function to check if a firewall rule exists and is enabled
function Is-FirewallRuleEnabled {
    param (
        [string]$ruleName
    )
    $ruleStatus = netsh advfirewall firewall show rule name="$ruleName" | Select-String -Pattern "Enabled: Yes"
    return $ruleStatus -ne $null
}

# Function to add and enable a firewall rule using netsh
function Add-FirewallRule {
    param (
        [string]$ruleName,
        [string]$program = "",
        [string]$protocol = "",
        [string]$localPort = ""
    )

    $command = "netsh advfirewall firewall add rule name=`"$ruleName`" dir=in action=allow profile=any enable=yes"

    if ($program -ne "") { $command += " program=$program" }
    if ($protocol -ne "") { $command += " protocol=$protocol" }
    if ($localPort -ne "") { $command += " localport=$localPort" }

    Invoke-Expression $command
}

# Function to enable a firewall rule using Enable-NetFirewallRule
function Enable-FirewallRule {
    param (
        [string]$ruleName
    )
    Enable-NetFirewallRule -DisplayName $ruleName
}

# Define the firewall rules to remediate
$firewallRules = @(
    @{
        Name = "Remote Desktop - Shadow (TCP-In)"
        Program = "%SystemRoot%\system32\RdpSa.exe"
        Protocol = "TCP"
        LocalPort = "Any"
    },
    @{
        Name = "Remote Desktop - User Mode (TCP-In)"
        Program = "%SystemRoot%\system32\svchost.exe"
        Protocol = "TCP"
        LocalPort = "3389"
    },
    @{
        Name = "Remote Desktop - User Mode (UDP-In)"
        Program = "%SystemRoot%\system32\svchost.exe"
        Protocol = "UDP"
        LocalPort = "3389"
    },
    @{
        Name = "File and Printer Sharing (Echo Request - ICMPv4-In)"
        Program = ""
        Protocol = "ICMPv4"
        LocalPort = ""
    },
    @{
        Name = "File and Printer Sharing (Echo Request - ICMPv6-In)"
        Program = ""
        Protocol = "ICMPv6"
        LocalPort = ""
    }
)

# Remediate the firewall rules
foreach ($rule in $firewallRules) {
    $ruleEnabled = Is-FirewallRuleEnabled -ruleName $rule.Name
    if (-not $ruleEnabled) {
        Add-FirewallRule -ruleName $rule.Name -program $rule.Program -protocol $rule.Protocol -localPort $rule.LocalPort
        Enable-FirewallRule -ruleName $rule.Name
    }
}
