# Script to check if Dell Peripheral Manager is installed

# Check if Dell Peripheral Manager is Installed and service is running
$dellPeripheralMgrService = Get-Service -Name "DPMService" -ErrorAction SilentlyContinue

if ($dellPeripheralMgrService.Status -eq "Running") {
    Write-Host "Dell Peripheral Manager is running" -ErrorAction SilentlyContinue
} else {
    Write-Host "Dell Peripheral Manager is not running" -ErrorAction SilentlyContinue
}

# Check if Dell Peripheral Manager is installed
if ($dellPeripheralMgrService) {
    Write-Host "Dell Peripheral Manager is installed"
    exit 1
} else {
    Write-Host "Dell Peripheral Manager is not installed"
    exit 0
}

# End of script


