# Enable automatic time zone detection
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate"
$propertyName = "Start"

# Check the current registry value
$currentValue = Get-ItemProperty -Path $registryPath -Name $propertyName

if ($currentValue.Start -ne 3) {
    # Set the registry value to enable automatic time zone detection
    Set-ItemProperty -Path $registryPath -Name $propertyName -Value 3
    Write-Host "Automatic time zone detection enabled."
} else {
    Write-Host "Automatic time zone detection is already enabled."
}

# Restart the Windows Time service to apply the changes
Restart-Service -Name "w32time"