<#
.SYNOPSIS
    Remediation Script - Remove Custom Lockscreen Settings
.DESCRIPTION
    Removes the LockScreenImagePath, LockScreenImageUrl, and LockScreenImageStatus 
    registry values and logs output to ProgramData.
#>

# Remediation
$AppName = "Remove Lockscreen"
$client = "FYNA"
$logPath = "$env:ProgramData\$client\logs"
$logFile = "$logPath\$AppName.log"

if (!(Test-Path -Path $logPath)) {
    New-Item -Path $logPath -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $logFile -Force

try {
    $LockScreenPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

    if (Test-Path -Path $LockScreenPath) {
        Remove-ItemProperty -Path $LockScreenPath -Name "LockScreenImagePath" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $LockScreenPath -Name "LockScreenImageUrl" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $LockScreenPath -Name "LockScreenImageStatus" -ErrorAction SilentlyContinue

        Write-Host "Lock screen registry values removed successfully."

        # Remove the entire key if no remaining values exist
        $key = Get-Item -Path $LockScreenPath
        if ($key.Property.Count -eq 0) {
            Remove-Item -Path $LockScreenPath -Force
            Write-Host "Lock screen registry key removed as it was empty."
        }
    } else {
        Write-Host "Lock screen registry key does not exist."
    }
} catch {
    Write-Host "Failed to revert lock screen settings! Error: $_"
}

Stop-Transcript