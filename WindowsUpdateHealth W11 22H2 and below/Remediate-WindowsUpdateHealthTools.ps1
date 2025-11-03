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

# Determine the installer to use
$build = ([System.Environment]::OSVersion.Version).Build

if ($build -ge 22621) {
    # Windows 11 22H2+
    $path = Join-Path $extractDest 'Windows 11 22H2+\UpdHealthTools.msi'
} elseif ($build -eq 22000) {
    # Windows 11 21H2
    $path = Join-Path $extractDest 'Windows 11 21H2\UpdHealthTools.msi'
} elseif ($build -le 19045 ) {
    # Windows 10
    $path = Join-Path $extractDest 'Windows 10\UpdHealthTools.msi'
} else {
    Write-Host 'Flagrant system error'
    Exit 1
}

# Perform the installation
$msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i ""$path"" /quiet /norestart" -Wait -Passthru).ExitCode

# Clean up
Remove-Item -Path $extractDest -Recurse
Remove-Item -Path $downloadDest

# Report the outcome of the installation
Exit $msiExitCode