try {
    $bitlocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    $hasRecoveryKey = $bitlocker.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

    # Check if BitLocker is fully enabled and has a recovery password protector
    if ($bitlocker.ProtectionStatus -eq 'On' -and $bitlocker.VolumeStatus -eq 'FullyEncrypted' -and $hasRecoveryKey) {
        Write-Output "BitLocker is fully enabled on C: with an active recovery key."
        exit 0
    } else {
        Write-Output "BitLocker is either turned off, decrypting, or missing a recovery key on C:."
        exit 1
    }
} catch {
    Write-Error "Error querying BitLocker status: $_"
    exit 1
}