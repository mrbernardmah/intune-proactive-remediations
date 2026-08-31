try {
    $BL = Get-BitLockerVolume -MountPoint "C:"

# Retrieves Trusted Platform Module (TPM) information.
# The -ErrorAction SilentlyContinue suppresses errors if:
# - No TPM exists
# - TPM service is unavailable
# - Device does not support TPM
 
    $TPM = Get-Tpm -ErrorAction SilentlyContinue

# BitLocker can have multiple key protectors:
# This line filters the list and returns only Recovery Password protectors.
  
    $RecoveryProtector = $BL.KeyProtector | Where-Object {
        $_.KeyProtectorType -eq "RecoveryPassword"
    }

# Create an array of strings from the various information to report on.

    $Output = @(
        "Encrypted=$($BL.VolumeStatus)"
        "Protection=$($(if($BL.ProtectionStatus -eq 1){'On'}else{'Off'}))"
        "Method=$($BL.EncryptionMethod)"
        "Percent=$($BL.EncryptionPercentage)%"
        "TPM_Present=$($TPM.TpmPresent)"
        "TPM_Ready=$($TPM.TpmReady)"
        "RecoveryKey=$($(if($RecoveryProtector){'Yes'}else{'No'}))"
        "RecoveryKeyID=$($(if($RecoveryProtector){$RecoveryProtector[0].KeyProtectorId}else{'None'}))"
    ) -join " | "
# Combines all the array elements into a single string separated by pipes (|).

    Write-Output $Output
}
catch {
    Write-Output "BitLockerReport=ERROR | Message=$($_.Exception.Message)"
}

exit 0