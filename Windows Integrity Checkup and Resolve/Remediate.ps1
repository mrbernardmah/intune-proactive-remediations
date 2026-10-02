<#
.SYNOPSIS
    Remediation Script for Windows Integrity
#>

# Variables
$logDir  = "C:\ProgramData\Devicie\logs"
$logFile = "$logDir\SFC_Remediate.log"

# Create log directory if missing
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Log-Message {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
}

function Run-DISM {
    Log-Message "Running DISM /RestoreHealth..."
    $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
    Log-Message "DISM completed with exit code: $($process.ExitCode)"
    return $process.ExitCode
}

function Run-SFC {
    Log-Message "Running SFC /scannow..."
    $process = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
    Log-Message "SFC completed with exit code: $($process.ExitCode)"
    return $process.ExitCode
}

# Main Execution Flow
Log-Message "======================================"
Log-Message "Starting system file remediation routine"
Log-Message "======================================"

# Step 1: Repair Component Store first so SFC has a healthy source payload
$dismExitCode = Run-DISM

Start-Sleep -Seconds 5

# Step 2: Run SFC repair using the restored Component Store
$sfcExitCode = Run-SFC

# Log results
if ($sfcExitCode -eq 0) {
    Log-Message "Remediation successful: All integrity violations repaired."
    Write-Output "Remediation successful: System files restored."
    Exit 0
}
else {
    Log-Message "Remediation completed with code $sfcExitCode. Check CBS logs (C:\Windows\Logs\CBS\CBS.log) for details."
    Write-Output "Remediation completed with warnings/errors. Exit Code: $sfcExitCode"
    Exit 0
}