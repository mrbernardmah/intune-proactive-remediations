# Define the path to the file
$filePath = "C:\Program Files\Sophos\Endpoint Defense\SSPService.exe"

# Check if the file exists
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Host "Sophos agent detected."
	Exit 1
} else {
    Write-Host "Sophos Agent not detected."
	Exit 0
}
