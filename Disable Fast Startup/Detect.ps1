<#
.SYNOPSIS
    Detection script: checks whether Fast Startup (Hiberboot) is disabled.
.DESCRIPTION
    Exit 0 = compliant (HiberbootEnabled = 0), no remediation needed.
    Exit 1 = non-compliant (value missing or not 0), remediation will run.
    Run as SYSTEM in 64-bit PowerShell.
#>

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$ValueName    = "HiberbootEnabled"
$TargetValue  = 0

try {
    $CurrentValue = Get-ItemPropertyValue -Path $RegistryPath -Name $ValueName -ErrorAction Stop

    if ($CurrentValue -eq $TargetValue) {
        Write-Output "Compliant: Fast Startup is disabled ($ValueName = $CurrentValue)."
        exit 0
    }
    else {
        Write-Output "Non-compliant: Fast Startup is enabled ($ValueName = $CurrentValue)."
        exit 1
    }
}
catch {
    # Value missing: Windows treats a missing value as Fast Startup enabled
    Write-Output "Non-compliant: $ValueName not found under $RegistryPath."
    exit 1
}