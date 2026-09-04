<#
.SYNOPSIS
    BitLocker Detection Script for Protection Status is Off.
#>

try {
    # Retrieve BitLocker status for C: drive
    $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop

    # Check if Protection is ON and the drive is either fully encrypted or actively encrypting
    if ($bitlocker.ProtectionStatus -eq "On" -and ($bitlocker.VolumeStatus -eq "FullyEncrypted" -or $bitlocker.VolumeStatus -eq "EncryptionInProgress")) {
        Write-Output "COMPLIANT: BitLocker is ON and drive C: is protected/encrypting."
        exit 0
    } else {
        Write-Output "NON-COMPLIANT: BitLocker protection is OFF or drive C: is decrypted."
        exit 1
    }
} catch {
    Write-Error "ERROR: Failed to query BitLocker status. Details: $_"
    exit 1
}