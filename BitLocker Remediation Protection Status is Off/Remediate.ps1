<#
.SYNOPSIS
    BitLocker Remediation Script for Protection is turned off.
    Enables BitLocker on C: drive, backs up recovery key to Entra ID / Intune,
    and handles restart requirements (Error 0x8031004e).
#>

try {
    Write-Output "Initiating BitLocker encryption on C: drive..."

    # Check TPM readiness prior to enabling
    $tpm = Get-Tpm
    if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) {
        Write-Error "ERROR: TPM is missing or not ready. Cannot enable BitLocker."
        exit 1
    }

    # Enable BitLocker on C: using manage-bde
    $result = manage-bde -on C: -UsedSpaceOnly -RecoveryPassword 2>&1

    # Check if a restart is required (Error code 0x8031004e)
    if ($result -match "0x8031004e" -or $result -match "restart your computer") {
        Write-Warning "RESTART REQUIRED: System must be restarted before enabling BitLocker (0x8031004e)."
       
        # Initiate a restart in 60 seconds (allows Intune to collect the log output first)
        shutdown.exe /r /t 60 /c "BitLocker setup requires a restart to proceed."
       
        # Exit with failure so Intune re-evaluates the remediation on the next sync after reboot
        exit 1
    }

    Write-Output $result

    # Re-check status to verify execution
    $bitlocker = Get-BitLockerVolume -MountPoint "C:"

    if ($bitlocker.ProtectionStatus -eq "On" -or $bitlocker.VolumeStatus -eq "EncryptionInProgress") {
       
        # Locate the 48-digit Recovery Password key protector
        $recoveryProtector = $bitlocker.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

        if ($recoveryProtector) {
            # Backup the recovery key to Entra ID / Intune
            BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $recoveryProtector.KeyProtectorId
            Write-Output "REMEDIATION SUCCESS: BitLocker enabled and recovery key backed up to Entra ID / Intune."
        } else {
            Write-Warning "BitLocker enabled, but no Recovery Password protector was found to backup."
        }

        exit 0
    } else {
        Write-Error "REMEDIATION FAILED: manage-bde executed, but ProtectionStatus is still OFF."
        exit 1
    }
} catch {
    Write-Error "ERROR: An exception occurred during BitLocker remediation: $_"
    exit 1
}
