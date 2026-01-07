# PowerShell script to disable "Automatically detect settings" in Internet Options
# Path to the registry key
$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# Value to set
$ValueName = "AutoDetect"

# Check if the registry key exists, if not, create it
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Set the registry value to 0 to disable "Automatically detect settings"
Set-ItemProperty -Path $RegPath -Name $ValueName -Value 0 -Type DWORD -Force

Write-Host "Successfully disabled 'Automatically detect settings' in Internet Options."