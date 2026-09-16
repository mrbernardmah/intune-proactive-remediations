try {
    # 1. Initiate decryption / turn off BitLocker on C:
    Write-Output "Initiating manage-bde -off C:..."
    manage-bde -off C: | Out-Null

    # Wait for decryption to fully complete before attempting re-encryption
    Write-Output "Waiting for drive C: to reach 'FullyDecrypted' status..."
    do {
        Start-Sleep -Seconds 10
        $volumeStatus = (Get-BitLockerVolume -MountPoint "C:").VolumeStatus
    } while ($volumeStatus -ne 'FullyDecrypted')

    # 2. Activate BitLocker on the C: drive (Suppressed warning/info output streams)
    Write-Output "Enabling BitLocker on C: drive..."
    Enable-BitLocker -MountPoint "C:" -RecoveryPasswordProtector -UsedSpaceOnly -ErrorAction Stop 3>$null 6>$null | Out-Null

    # 3. Retrieve the BitLocker recovery key protector
    $bitlocker = Get-BitLockerVolume -MountPoint "C:"
    $recoveryKeyProtector = $bitlocker.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }

    if (-not $recoveryKeyProtector) {
        throw "Recovery Password protector was not found after enabling BitLocker."
    }

    # 4. Save the recovery key to a file on C:\ with the computer name
    $computerName = $env:COMPUTERNAME
    $keyFileName = "${computerName}_Bitlocker.txt"
    $keyFilePath = Join-Path -Path "C:\" -ChildPath $keyFileName
    $recoveryKeyProtector.RecoveryPassword | Out-File -FilePath $keyFilePath -Force
    Write-Output "Recovery key saved locally to $keyFilePath"

    # 5. Backup the recovery key to Microsoft Entra ID / Intune
    Write-Output "Uploading recovery key to Microsoft Entra ID / Intune..."
    BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $recoveryKeyProtector.KeyProtectorId -ErrorAction Stop

    Write-Output "BitLocker enabled, local file written, and recovery key successfully backed up to Intune."
    exit 0
} catch {
    Write-Error "Remediation failed: $_"
    exit 1
}
