[CmdletBinding()]
param(
    [string]$MountPoint = $env:SystemDrive
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'COMPLIANT', 'NON-COMPLIANT')]
        [string]$Level = 'INFO'
    )

    Write-Output "[$Level] $Message"
}

function Exit-Compliant {
    param([string]$Message)

    Write-Log -Level 'COMPLIANT' -Message $Message
    exit 0
}

function Exit-NonCompliant {
    param([string]$Message)

    Write-Log -Level 'NON-COMPLIANT' -Message $Message
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

try {
    $MountPoint = Normalize-MountPoint -Value $MountPoint
    Write-Log "Starting BitLocker AES-256 detection for OS drive $MountPoint."

    if (-not (Test-IsWindows)) {
        Exit-NonCompliant 'This script must run on Windows. Intune proactive remediations should target Windows devices only.'
    }

    if (-not (Test-IsSystemOrAdmin)) {
        Exit-NonCompliant 'This script must run as LocalSystem or local administrator. In Intune, set "Run scripts using logged-on credentials" to "No".'
    }

    foreach ($commandName in 'Get-Tpm', 'Get-BitLockerVolume') {
        if (-not (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
            Exit-NonCompliant "Required command '$commandName' is not available. Run in 64-bit Windows PowerShell with BitLocker management tools available."
        }
    }

    $tpm = Get-Tpm
    Write-Log "TPM state: Present=$($tpm.TpmPresent), Enabled=$($tpm.TpmEnabled), Ready=$($tpm.TpmReady)."

    if (-not $tpm.TpmPresent) {
        Exit-NonCompliant 'TPM is not present.'
    }

    if (-not $tpm.TpmEnabled) {
        Exit-NonCompliant 'TPM is present but not enabled.'
    }

    if (-not $tpm.TpmReady) {
        Exit-NonCompliant 'TPM is present but not ready.'
    }

    $volume = Get-BitLockerVolume -MountPoint $MountPoint
    if (-not $volume) {
        Exit-NonCompliant "BitLocker volume $MountPoint was not found."
    }

    Write-Log "Volume state: ProtectionStatus=$($volume.ProtectionStatus), EncryptionMethod=$($volume.EncryptionMethod), VolumeStatus=$($volume.VolumeStatus), EncryptionPercentage=$($volume.EncryptionPercentage)."

    if ($volume.ProtectionStatus -ne 'On') {
        Exit-NonCompliant 'BitLocker protection is not On.'
    }

    if ($volume.EncryptionMethod -ne 'XtsAes256') {
        Exit-NonCompliant "Encryption method is '$($volume.EncryptionMethod)', expected 'XtsAes256'."
    }

    if ($volume.VolumeStatus -ne 'FullyEncrypted') {
        Exit-NonCompliant "Volume status is '$($volume.VolumeStatus)', expected 'FullyEncrypted'."
    }

    if ([int]$volume.EncryptionPercentage -ne 100) {
        Exit-NonCompliant "Encryption percentage is $($volume.EncryptionPercentage), expected 100."
    }

    Exit-Compliant "Device is compliant. $MountPoint is protected with BitLocker XtsAes256, fully encrypted, and TPM is ready."
}
catch {
    Write-Log -Level 'ERROR' -Message "Detection failed: $($_.Exception.Message)"
    exit 1
}
