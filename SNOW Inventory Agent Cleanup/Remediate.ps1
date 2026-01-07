# Detect if Snow agent service is running and stop it
$service = Get-Service -Name "SnowInventoryAgent5" -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name "SnowInventoryAgent5" -Force 
    Write-Output "Snow Inventory Agent service has been successfully stopped."
} else {
    Write-Output "Snow Inventory Agent service is not running."
}

Start-Sleep -Seconds 30

# Uninstall Snow Inventory Agent
uninstall-package -name "Snow Inventory Agent" -ErrorAction SilentlyContinue


# Check For Snow Inventory Agent Folders
$program86path = get-item -path "C:\Program Files (x86)\Snow Software" -ErrorAction SilentlyContinue
$programpath = get-item -path "C:\Program Files\Snow Software" -ErrorAction SilentlyContinue
$programdata = Get-Item -path "C:\ProgramData\SnowSoftware" -ErrorAction SilentlyContinue

if ($program86path) {
    Remove-Item -Path "C:\Program Files (x86)\Snow Software" -Recurse -Force
    Write-Output "Snow Inventory Agent folder has been successfully removed from Program Files (x86)."
} else {
    Write-Output "Snow Inventory Agent folder is not present in Program Files (x86)."
}

if ($programdata) {
    Remove-Item -Path "C:\ProgramData\SnowSoftware" -Recurse -Force
    Write-Output "Snow Inventory Agent folder has been successfully removed from ProgramData."
} else {
    Write-Output "Snow Inventory Agent folder is not present in ProgramData."
}

if ($programpath) {
    Remove-Item -Path "C:\Program Files\Snow Software" -Recurse -Force
    Write-Output "Snow Inventory Agent folder has been successfully removed from Program Files."
} else {
    Write-Output "Snow Inventory Agent folder is not present in Program Files."
}

# Check if Snow Inventory Agent is installed
$SNOWpackage = get-package -name "Snow Inventory Agent" -ErrorAction SilentlyContinue
if ($SNOWpackage) {
    Write-Output "Snow Inventory Agent is still installed."
    exit 1
} else {
    Write-Output "Snow Inventory Agent has been successfully uninstalled."
    exit 0
}