<#
.SYNOPSIS
    Detection script: checks whether Fast Startup (Hiberboot) is enabled.
.DESCRIPTION
    Exit 0 = compliant (HiberbootEnabled = 1 and hibernation available).
    Exit 1 = non-compliant, remediation will run.
    Run as SYSTEM in 64-bit PowerShell.
#>

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$ValueName    = "HiberbootEnabled"
$TargetValue  = 1

# Fast Startup needs hibernation; if hibernation is off, the registry value alone does nothing
$PowerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
$HibernateEnabled = (Get-ItemProperty -Path $PowerPath -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled

if ($HibernateEnabled -eq 0) {
    Write-Output "Non-compliant: hibernation is disabled, so Fast Startup cannot work."
    exit 1
}

try {
    $CurrentValue = Get-ItemPropertyValue -Path $RegistryPath -Name $ValueName -ErrorAction Stop

    if ($CurrentValue -eq $TargetValue) {
        Write-Output "Compliant: Fast Startup is enabled ($ValueName = $CurrentValue)."
        exit 0
    }
    else {
        Write-Output "Non-compliant: Fast Startup is disabled ($ValueName = $CurrentValue)."
        exit 1
    }
}
catch {
    Write-Output "Non-compliant: $ValueName not found under $RegistryPath."
    exit 1
}