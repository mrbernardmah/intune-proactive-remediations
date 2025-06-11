## Detection Script

## Variables
$DisplayName = "Windows Subsystem for Linux"
$FeatureName1 = "Microsoft-Windows-Subsystem-Linux"
$FeatureName2 = "VirtualMachinePlatform"

## Get the list of installed applications from the registry
$InstalledApps = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue

## Find the application by display name
$Application = $InstalledApps | Where-Object { $_.DisplayName -eq $DisplayName }

## Find the first Feature
$Feature1 = Get-CimInstance -Query "SELECT * FROM Win32_OptionalFeature WHERE Name = '$FeatureName1'"

## Find the second Feature
$Feature2 = Get-CimInstance -Query "SELECT * FROM Win32_OptionalFeature WHERE Name = '$FeatureName2'"


if ($Application -and $Feature1.InstallState -and $Feature2.InstallState -eq 1) {
    Write-Host "Application and features are installed"
    exit 0
} elseif ($Application) {
    Write-Host "Application is installed but features are not"
    exit 1
} else {
    Write-Host "Application is not installed"
    exit 0
}
