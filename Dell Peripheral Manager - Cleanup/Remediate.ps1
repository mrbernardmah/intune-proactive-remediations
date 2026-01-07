# Script is used to uninstall Dell Peripheral Manager from the system
# Confirm Dell Peripheral Manager is installed
if (!(Test-Path "C:\Program Files\Dell\Dell Peripheral Manager")) {
    Write-Output "Dell Peripheral Manager is not installed."
} else {
    Write-Output "Dell Peripheral Manager is installed."
}

# Uninstall Dell Peripheral Manager
$uninstallPath = "C:\Program Files\Dell\Dell Peripheral Manager\Uninstall.exe"
if (Test-Path $uninstallPath) {
    Start-Process -FilePath $uninstallPath -ArgumentList "/S" -Wait
} else {
    Write-Error "Uninstall executable not found."
}

# Check for Dell Peripheral Manager folders
$programdata = Get-Item -Path "C:\ProgramData\Dell" -ErrorAction SilentlyContinue

if ($programdata) {
    Remove-Item -Path "C:\ProgramData\Dell" -Recurse -Force
    Write-Output "Dell Peripheral Manager folder has been successfully removed from ProgramData."
} else {
    Write-Output "Dell Peripheral Manager folder is not present in ProgramData."
}

# Confirm Dell Peripheral Manager has been uninstalled
if (Test-Path $uninstallPath) {
    Write-Output "Dell Peripheral Manager is still installed."
    exit 1
} else {
    Write-Output "Dell Peripheral Manager has been successfully uninstalled."
    exit 0
}

# End of script