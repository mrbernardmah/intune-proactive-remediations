## Remediation Script

## Check if WSL is installed. If not, install it
$wsl = Get-CimInstance -Query "SELECT * FROM Win32_OptionalFeature WHERE Name = 'Microsoft-Windows-Subsystem-Linux'"
if ($wsl.InstallState -ne 1) {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
}

## Check if VMP is installed. If not, install it
$vmp = Get-CimInstance -Query "SELECT * FROM Win32_OptionalFeature WHERE Name = 'VirtualMachinePlatform'" -Query "SELECT * FROM Win32_OptionalFeature WHERE Name = 'VirtualMachinePlatform'"
if ($vmp.InstallState -ne 1) {
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
}