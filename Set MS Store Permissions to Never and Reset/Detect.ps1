# =======================================================================================
# DETECTION SCRIPT: Microsoft Store Restrictions & Reset
# =======================================================================================

$PackageFamilyName = "Microsoft.WindowsStore_8wekyb3d8bbwe"
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$PackageFamilyName"
$ValueName = "DisabledByUser"
$ExpectedValue = 2

# Check if the registry path exists
if (Test-Path $RegistryPath) {
    # Get the current value of DisabledByUser
    $CurrentValue = Get-ItemPropertyValue -Path $RegistryPath -Name $ValueName -ErrorAction SilentlyContinue

    if ($CurrentValue -eq $ExpectedValue) {
        Write-Host "Compliant: Microsoft Store background permission is set to 'Never'."
        Exit 0 # Compliant
    } else {
        Write-Warning "Non-Compliant: Background permission value is $CurrentValue (Expected: $ExpectedValue)."
        Exit 1 # Non-Compliant (Triggers Remediation)
    }
} else {
    Write-Warning "Non-Compliant: Registry path does not exist."
    Exit 1 # Non-Compliant (Triggers Remediation)
}