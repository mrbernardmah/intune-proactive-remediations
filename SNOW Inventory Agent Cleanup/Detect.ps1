# Check if Snow Inventory Agent is installed
$SNOWpackage = get-package -name "Snow Inventory Agent" -ErrorAction SilentlyContinue
if ($SNOWpackage) {
    Write-Output "Snow Inventory Agent is installed."
    exit 1
} else {
    Write-Output "Snow Inventory Agent is not installed."
    exit 0
}