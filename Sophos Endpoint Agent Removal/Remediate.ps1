# Define the path to the transcript log file
$transcriptPath = "C:\windows\temp\Remediation-Script-Sophos-Removal.log"
if (test-path $transcriptPath) {
	remove-item -path $transcriptPath -force
}
Start-Transcript -Path $transcriptPath -Append

# Define the path to the file
$filePath = "C:\Program Files\Sophos\Endpoint Defense\SSPService.exe"

# Check if the file exists
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Host "Sophose detected."
	
	if (test-path "C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe") {
		$uninstallerPath = "C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe"

		# Define the arguments for the uninstaller
		$arguments = "--quiet"

		# Start the uninstaller process
		Start-Process -FilePath $uninstallerPath -ArgumentList $arguments -Wait
		start-sleep -s 2
		
		if (Test-Path -Path $filePath -PathType Leaf) {
			Write-Host "Sophose uninstall failed. ZAP tool removal required"
			Exit 2
		} else {
			Write-Host "Sophose removed."
			Exit 0
		}
		
	} else {
		Write-Host "Sophose not uninstaller not found. ZAP tool removal required"
		Exit 2
	}
} else {
	Write-Host "Sophose not detected."
	Exit 0
}

# Stop transcript logging
Stop-Transcript