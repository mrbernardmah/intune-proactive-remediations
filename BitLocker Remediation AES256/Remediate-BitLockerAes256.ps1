[CmdletBinding()]
param(
    [string]$MountPoint = $env:SystemDrive,

    [switch]$DryRun,

    [switch]$WaitForFullEncryption,

    [ValidateRange(1, 1440)]
    [int]$MaxWaitMinutes = 240,

    [ValidateRange(5, 300)]
    [int]$PollSeconds = 30
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION', 'DRYRUN', 'BLOCKED', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    Write-Output "[$Level] $Message"
}

function Complete-Success {
    param([string]$Message)

    Write-Log -Level 'SUCCESS' -Message $Message
    exit 0
}

function Complete-Blocked {
    param([string]$Message)

    Write-Log -Level 'BLOCKED' -Message $Message
    exit 1
}

function Test-IsWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $true
    }

    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
}

function Test-IsSystemOrAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return (
        $identity.IsSystem -or
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    )
}

function Normalize-MountPoint {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = 'C:'
    }

    $normalized = $Value.Trim().TrimEnd('\')
    if ($normalized -notmatch ':$') {
        $normalized = "${normalized}:"
    }

    return $normalized.ToUpperInvariant()
}

function Test-RequiredCommand {
    param([string[]]$Names)

    foreach ($commandName in $Names) {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            Complete-Blocked "Required command '$commandName' is not available. Run in 64-bit Windows PowerShell with BitLocker management tools available."
        }
    }
}

function Invoke-Change {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if ($DryRun) {
        Write-Log -Level 'DRYRUN' -Message "Would $Description."
        return $null
    }

    Write-Log -Level 'ACTION' -Message $Description
    return & $ScriptBlock
}

function Get-OsVolume {
    param([string]$TargetMountPoint)

    return Get-BitLockerVolume -MountPoint $TargetMountPoint
}

function Test-TpmReady {
    $tpm = Get-Tpm
    Write-Log "TPM state: Present=$($tpm.TpmPresent), Enabled=$($tpm.TpmEnabled), Ready=$($tpm.TpmReady)."

    if (-not $tpm.TpmPresent) {
        Complete-Blocked 'TPM is not present. BitLocker with TPM cannot be enabled by this remediation.'
    }

    if (-not $tpm.TpmEnabled) {
        Complete-Blocked 'TPM is present but not enabled. Enable TPM in firmware/BIOS or device management first.'
    }

    if (-not $tpm.TpmReady) {
        Complete-Blocked 'TPM is present but not ready. Initialize or clear/prepare TPM according to your organization policy before retrying.'
    }
}

function Get-RecoveryPasswordProtector {
    param($Volume)

    return @($Volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1)
}

function Ensure-RecoveryPasswordProtector {
    param([string]$TargetMountPoint)

    $volume = Get-OsVolume -TargetMountPoint $TargetMountPoint
    $protector = Get-RecoveryPasswordProtector -Volume $volume

    if ($protector) {
        Write-Log "Recovery password protector already exists: $($protector.KeyProtectorId)."
        return $protector
    }

    $result = Invoke-Change -Description "add a recovery password protector to $TargetMountPoint" -ScriptBlock {
        Add-BitLockerKeyProtector -MountPoint $TargetMountPoint -RecoveryPasswordProtector
    }

    if ($DryRun) {
        return $null
    }

    $volume = Get-OsVolume -TargetMountPoint $TargetMountPoint
    return Get-RecoveryPasswordProtector -Volume $volume
}

function Backup-RecoveryPasswordToAad {
    param(
        [string]$TargetMountPoint,
        $RecoveryProtector
    )

    if (-not $RecoveryProtector) {
        Write-Log -Level 'WARN' -Message 'No recovery password protector is available to back up yet.'
        return
    }

    if (-not (Get-Command -Name 'BackupToAAD-BitLockerKeyProtector' -ErrorAction SilentlyContinue)) {
        Write-Log -Level 'WARN' -Message 'BackupToAAD-BitLockerKeyProtector is not available on this device. Recovery key backup was skipped.'
        return
    }

    Invoke-Change -Description "back up recovery password protector $($RecoveryProtector.KeyProtectorId) to Entra ID/Azure AD" -ScriptBlock {
        BackupToAAD-BitLockerKeyProtector -MountPoint $TargetMountPoint -KeyProtectorId $RecoveryProtector.KeyProtectorId
    } | Out-Null
}

function Resume-IfNeeded {
    param(
        [string]$TargetMountPoint,
        $Volume
    )

    $isProtectionOff = $Volume.ProtectionStatus -ne 'On'
    $isEncryptionSuspended = $Volume.VolumeStatus -eq 'EncryptionSuspended'

    if (-not $isProtectionOff -and -not $isEncryptionSuspended) {
        Write-Log 'No suspended BitLocker protection or encryption state was detected.'
        return
    }

    Invoke-Change -Description "resume BitLocker protection/encryption on $TargetMountPoint" -ScriptBlock {
        Resume-BitLocker -MountPoint $TargetMountPoint
    } | Out-Null
}

function Wait-UntilFullyEncrypted {
    param([string]$TargetMountPoint)

    if (-not $WaitForFullEncryption) {
        Write-Log 'Not waiting for full encryption. Windows will continue encryption in the background.'
        return
    }

    if ($DryRun) {
        Write-Log -Level 'DRYRUN' -Message "Would wait until $TargetMountPoint reaches 100 percent encryption."
        return
    }

    $deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
    do {
        $volume = Get-OsVolume -TargetMountPoint $TargetMountPoint
        Write-Log "Encryption progress: VolumeStatus=$($volume.VolumeStatus), EncryptionPercentage=$($volume.EncryptionPercentage)."

        if ($volume.VolumeStatus -eq 'FullyEncrypted' -and [int]$volume.EncryptionPercentage -eq 100) {
            Write-Log "$TargetMountPoint reached full encryption."
            return
        }

        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date) -lt $deadline)

    Complete-Blocked "Timed out after $MaxWaitMinutes minutes waiting for $TargetMountPoint to reach 100 percent encryption."
}

try {
    $MountPoint = Normalize-MountPoint -Value $MountPoint
    Write-Log "Starting BitLocker AES-256 remediation for OS drive $MountPoint. DryRun=$($DryRun.IsPresent), WaitForFullEncryption=$($WaitForFullEncryption.IsPresent)."

    if (-not (Test-IsWindows)) {
        Complete-Blocked 'This script must run on Windows. Intune proactive remediations should target Windows devices only.'
    }

    if (-not (Test-IsSystemOrAdmin)) {
        Complete-Blocked 'This script must run as LocalSystem or local administrator. In Intune, set "Run scripts using logged-on credentials" to "No".'
    }

    Test-RequiredCommand -Names @(
        'Get-Tpm',
        'Get-BitLockerVolume',
        'Enable-BitLocker',
        'Add-BitLockerKeyProtector',
        'Resume-BitLocker'
    )

    Test-TpmReady

    $volume = Get-OsVolume -TargetMountPoint $MountPoint
    if (-not $volume) {
        Complete-Blocked "BitLocker volume $MountPoint was not found."
    }

    Write-Log "Current volume state: ProtectionStatus=$($volume.ProtectionStatus), EncryptionMethod=$($volume.EncryptionMethod), VolumeStatus=$($volume.VolumeStatus), EncryptionPercentage=$($volume.EncryptionPercentage)."

    $encryptionMethod = [string]$volume.EncryptionMethod
    $volumeStatus = [string]$volume.VolumeStatus
    $encryptionPercentage = [int]$volume.EncryptionPercentage

    if ($encryptionMethod -notin @('None', 'XtsAes256')) {
        Complete-Blocked "Volume is already encrypted or configured with '$encryptionMethod'. Windows cannot change the BitLocker encryption method in place. Decrypt and re-encrypt as a separate migration if AES-256 is required."
    }

    if ($volumeStatus -in @('DecryptionInProgress', 'DecryptionSuspended')) {
        Complete-Blocked "Volume status is '$volumeStatus'. This remediation will not resume or interrupt decryption. Review the device manually before re-encrypting with XtsAes256."
    }

    if ($encryptionMethod -eq 'XtsAes256') {
        $recoveryProtector = Ensure-RecoveryPasswordProtector -TargetMountPoint $MountPoint
        Backup-RecoveryPasswordToAad -TargetMountPoint $MountPoint -RecoveryProtector $recoveryProtector
        Resume-IfNeeded -TargetMountPoint $MountPoint -Volume $volume

        if ($volumeStatus -eq 'FullyEncrypted' -and $encryptionPercentage -eq 100 -and $volume.ProtectionStatus -eq 'On') {
            Complete-Success "$MountPoint is already compliant with XtsAes256, full encryption, and protection On."
        }

        Wait-UntilFullyEncrypted -TargetMountPoint $MountPoint
        Complete-Success "$MountPoint is using XtsAes256 and Windows is allowed to continue or complete encryption."
    }

    if ($volumeStatus -in @('EncryptionInProgress', 'EncryptionSuspended') -and $encryptionMethod -eq 'None') {
        Complete-Blocked "Volume is encrypting but the encryption method is '$encryptionMethod'. Manual review is required before this remediation changes anything."
    }

    $recoveryProtector = Ensure-RecoveryPasswordProtector -TargetMountPoint $MountPoint

    Invoke-Change -Description "enable BitLocker on $MountPoint with XtsAes256, TPM protector, used-space-only encryption, and skip hardware test" -ScriptBlock {
        Enable-BitLocker `
            -MountPoint $MountPoint `
            -EncryptionMethod XtsAes256 `
            -UsedSpaceOnly `
            -TpmProtector `
            -SkipHardwareTest
    } | Out-Null

    if (-not $DryRun) {
        $volume = Get-OsVolume -TargetMountPoint $MountPoint
        $recoveryProtector = Get-RecoveryPasswordProtector -Volume $volume
    }

    Backup-RecoveryPasswordToAad -TargetMountPoint $MountPoint -RecoveryProtector $recoveryProtector
    Wait-UntilFullyEncrypted -TargetMountPoint $MountPoint

    if ($DryRun) {
        Complete-Success 'Dry run completed. No BitLocker settings were changed.'
    }

    Complete-Success "$MountPoint remediation started or completed successfully. Run detection again after encryption reaches 100 percent."
}
catch {
    Write-Log -Level 'ERROR' -Message "Remediation failed: $($_.Exception.Message)"
    exit 1
}
