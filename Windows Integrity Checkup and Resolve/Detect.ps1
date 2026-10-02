<#
.SYNOPSIS
    Detection Script for Windows Integrity
#>

# Variables
$logDir  = "C:\ProgramData\Devicie\logs"
$logFile = "$logDir\SFC_Detect.log"

# Create log directory if missing
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log-Message {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
}

Log-Message "Starting system integrity detection scan..."

# Run SFC in verify-only mode (non-destructive)
$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/verifyonly" -NoNewWindow -Wait -PassThru
$sfcExitCode = $sfcProcess.ExitCode

# Check DISM Component Store state
$dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /CheckHealth" -NoNewWindow -Wait -PassThru
$dismExitCode = $dismProcess.ExitCode

# Output and exit code logic for Intune/RMM
if ($sfcExitCode -eq 0 -and $dismExitCode -eq 0) {
    Log-Message "Detection result: System integrity intact. No remediation needed."
    Write-Output "Compliant: No system file corruption detected."
    Exit 0
}
else {
    Log-Message "Detection result: Corruption found. (SFC Code: $sfcExitCode, DISM Code: $dismExitCode)"
    Write-Output "Non-Compliant: System file corruption detected."
    Exit 1
}