#########################
#remediate.ps1         #
########################

# Paths for registry keys
$keyUpdate = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
$keyWindowsUpdate = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Registry values to remove from the Update registry path
$propertiesToRemove = @(
    "PauseQualityUpdatesStartTime",
    "PauseFeatureUpdatesStartTime",
    "PauseFeatureUpdatesStartTime_ProviderSet",
    "PauseQualityUpdatesStartTime_ProviderSet",
    "PauseFeatureUpdatesStartTime_WinningProvider",
    "PauseQualityUpdatesStartTime_WinningProvider",
    "PauseQualityUpdates_WinningProvider",
    "PauseFeatureUpdates_WinningProvider"
)

# Remove specified registry values if they exist
foreach ($property in $propertiesToRemove) {
    try {
        if ((Get-ItemProperty -Path $keyUpdate -Name $property -ErrorAction SilentlyContinue) -ne $null) {
            Remove-ItemProperty -Path $keyUpdate -Name $property -ErrorAction Stop -Force
            Write-Host "$property has been removed from $keyUpdate."
        }
    } catch {
        Write-Host "Failed to remove $property. Error: $_"
    }
}

# Remove PauseDeferrals if it exists in the Windows Update registry path
try {
    if ((Get-ItemProperty -Path $keyWindowsUpdate -Name "PauseDeferrals" -ErrorAction SilentlyContinue) -ne $null) {
        Remove-ItemProperty -Path $keyWindowsUpdate -Name "PauseDeferrals" -ErrorAction Stop -Force
        Write-Host "PauseDeferrals has been removed from $keyWindowsUpdate."
    }
} catch {
    Write-Host "Failed to remove PauseDeferrals. Error: $_"
}

# Ensure PauseFeatureUpdates and PauseQualityUpdates are set to zero
try {
    Set-ItemProperty -Path $keyUpdate -Name "PauseFeatureUpdates" -Value 0 -ErrorAction Stop -Force
    Write-Host "PauseFeatureUpdates has been set to zero."
} catch {
    Write-Host "Failed to set PauseFeatureUpdates to zero. Error: $_"
}

try {
    Set-ItemProperty -Path $keyUpdate -Name "PauseQualityUpdates" -Value 0 -ErrorAction Stop -Force
    Write-Host "PauseQualityUpdates has been set to zero."
} catch {
    Write-Host "Failed to set PauseQualityUpdates to zero. Error: $_"
}

# Final check to confirm all specified keys are deleted and required values are zero
$missingProperties = @()
foreach ($property in $propertiesToRemove) {
    if ((Get-ItemProperty -Path $keyUpdate -Name $property -ErrorAction SilentlyContinue) -ne $null) {
        $missingProperties += $property
    }
}

$PauseFeatureUpdatesValue = (Get-ItemProperty -Path $keyUpdate -Name "PauseFeatureUpdates" -ErrorAction SilentlyContinue).PauseFeatureUpdates
$PauseQualityUpdatesValue = (Get-ItemProperty -Path $keyUpdate -Name "PauseQualityUpdates" -ErrorAction SilentlyContinue).PauseQualityUpdates

# Check if any required properties still exist or if PauseFeatureUpdates/PauseQualityUpdates are not zero
if ($missingProperties.Count -eq 0 -and $PauseFeatureUpdatesValue -eq 0 -and $PauseQualityUpdatesValue -eq 0) {
    Write-Host "Remediation successful: All specified keys are deleted, and PauseFeatureUpdates/PauseQualityUpdates are set to zero."
    Exit 0 
} else {
    Write-Host "Remediation failed: The following keys still exist or values are incorrect:"
    if ($missingProperties.Count -gt 0) {
        Write-Host " - Remaining properties: $missingProperties"
    }
    if ($PauseFeatureUpdatesValue -ne 0) {
        Write-Host " - PauseFeatureUpdates is not zero (current value: $PauseFeatureUpdatesValue)"
    }
    if ($PauseQualityUpdatesValue -ne 0) {
        Write-Host " - PauseQualityUpdates is not zero (current value: $PauseQualityUpdatesValue)"
    }
     Exit 1 
}
