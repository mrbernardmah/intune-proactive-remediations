#########################
#detect.ps1            #
#########################

# Paths for registry keys
$keyUpdate = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
$keyWindowsUpdate = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"

# Load values from the Update registry path
$valUpdate = (Get-Item $keyUpdate)
$PauseQualityUpdatesStartTime = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseQualityUpdatesStartTime"
$PauseFeatureUpdatesStartTime = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseFeatureUpdatesStartTime"
$PauseFeatureUpdatesStartTimeProvider = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseFeatureUpdatesStartTime_ProviderSet"
$PauseQualityUpdatesStartTimeProvider = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseQualityUpdatesStartTime_ProviderSet"
$PauseFeatureUpdates = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseFeatureUpdates"
$PauseQualityUpdates = (Get-Item $keyUpdate -EA Ignore).Property -contains "PauseQualityUpdates"

$PauseQualityUpdatesStartTimeValue = $valUpdate.GetValue("PauseQualityUpdatesStartTime", $null)
$PauseFeatureUpdatesStartTimeValue = $valUpdate.GetValue("PauseFeatureUpdatesStartTime", $null)
$PauseFeatureUpdatesValue = $valUpdate.GetValue("PauseFeatureUpdates", $null)
$PauseQualityUpdatesValue = $valUpdate.GetValue("PauseQualityUpdates", $null)

# Check for PauseDeferrals key in the Windows Update registry path
$PauseDeferrals = (Get-Item $keyWindowsUpdate -EA Ignore).Property -contains "PauseDeferrals"
$PauseDeferralsValue = (Get-ItemProperty -Path $keyWindowsUpdate -Name "PauseDeferrals" -ErrorAction SilentlyContinue).PauseDeferrals

# Check if PauseDeferrals is set
if ($PauseDeferrals -and $PauseDeferralsValue -eq 1) {
    Write-Host "PauseDeferrals is still configured!"
    Exit 1
}

# Existing checks for other pause settings
if (($PauseQualityUpdatesStartTimeValue -ne '') -and ($PauseQualityUpdatesStartTimeProvider -eq $true)) {
    Write-Host "Pause Quality Updates StartTime is still configured!"
    Exit 1
}
if (($PauseFeatureUpdatesStartTimeValue -ne '') -and ($PauseFeatureUpdatesStartTimeProvider -eq $true)) {
    Write-Host "Pause Feature Updates StartTime is still configured!"
    Exit 1
}
if (($PauseQualityUpdates -eq $true) -and ($PauseQualityUpdatesValue -eq '1')) {
    Write-Host "Pause Quality Updates is still configured!"
    Exit 1
}
if (($PauseFeatureUpdates -eq $true) -and ($PauseFeatureUpdatesValue -eq '1')) {
    Write-Host "Pause Feature Updates is still configured!"
    Exit 1
} else {
    Write-Host "Quality and Feature updates are not paused anymore"
    Exit 0
}