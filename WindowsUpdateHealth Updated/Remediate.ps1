# Download the tool
$downloadUri = 'https://download.microsoft.com/download/d/7/e/d7e9fd79-e6fe-4036-85df-c60254f50d90/Expedite_packages.zip'
$downloadDest = Join-Path $env:TEMP 'Expedite_packages.zip'
$extractDest = Join-Path $env:TEMP 'Expedite_packages'

try {
    if (Test-Path $downloadDest) { Remove-Item $downloadDest -Force }
    Invoke-WebRequest -Uri $downloadUri -OutFile $downloadDest
} catch {
    Write-Host 'Failed to download installation media'
    Exit 1
}

try {
    if (Test-Path $extractDest) { Remove-Item $extractDest -Recurse }
    Expand-Archive -Path $downloadDest -DestinationPath $env:TEMP
}
catch {
    Write-Host 'Failed to expand archive'
    Exit 1
}

# Uninstall any currently installed version
$AppName = "Microsoft Update Health Tools"
$UninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"

$keys = Get-ChildItem $UninstallKey | Get-ItemProperty | Where-Object { $_.DisplayName -eq $AppName }

foreach ($key in $keys) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $($key.PSChildName) /quiet /norestart" -Wait
}

# Determine the installer to use - MODIFIED TO ONLY ALLOW ONE PATH
$build = ([System.Environment]::OSVersion.Version).Build

# ALWAYS use the Windows 11 22H2+ installer package to ensure maximum compatibility with newer systems
$path = Join-Path $extractDest 'Windows 11 22H2+\UpdHealthTools.msi'

# Perform the installation
$msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i ""$path"" /quiet /norestart" -Wait -Passthru).ExitCode

# Clean up
Remove-Item -Path $extractDest -Recurse
Remove-Item -Path $downloadDest

# NEW: Force to run service 'Microsoft Update Health Service' if installation was successful (ExitCode 0)
if ($msiExitCode -eq 0) {
    Write-Host 'Installation successful. Forcing "Microsoft Update Health Service" to run...'
    # Use 'Set-Service' to ensure the service is running
    try {
        Set-Service -Name "UsoSvc" -Status Running -ErrorAction Stop
        Write-Host 'Service started successfully.'
    } catch {
        Write-Host "Failed to start service: $($_.Exception.Message)"
    }
} else {
    Write-Host "Installation failed with exit code: $msiExitCode"
}

# Report the outcome of the installation
Exit $msiExitCode