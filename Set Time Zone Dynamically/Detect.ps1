# Variables for registry path and property name
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate"
$propertyName = "Start"

# Check the current registry value
$currentValue = Get-ItemProperty -Path $registryPath -Name $propertyName

# Check if automatic time zone detection is disabled
if ($currentValue.Start -ne 3) {
    # Return non-compliant status
    Write-Output "NonCompliant"
    Exit 1
} else {
    # Return compliant status
    Write-Output "Compliant"
    Exit 0
}