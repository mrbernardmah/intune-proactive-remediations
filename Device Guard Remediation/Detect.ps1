# Detection Script for Device Guard / HVCI
$Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"

$TargetSettings = @{
    "RequirePlatformSecurityFeatures" = 3
    "HypervisorEnforcedCodeIntegrity" = 1
    "HVCIMATRequired"                 = 1
}

# Check if the Registry key exists
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "Non-Compliant: DeviceGuard registry path does not exist."
    Exit 1
}

# Check each property value
foreach ($Name in $TargetSettings.Keys) {
    $CurrentValue = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    
    if ($null -eq $CurrentValue -or $CurrentValue -ne $TargetSettings[$Name]) {
        Write-Output "Non-Compliant: $Name is missing or misconfigured."
        Exit 1
    }
}

# If all checks pass
Write-Output "Compliant: DeviceGuard registry values are configured correctly."
Exit 0