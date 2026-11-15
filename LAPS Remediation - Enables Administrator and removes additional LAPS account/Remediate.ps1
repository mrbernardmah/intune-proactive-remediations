<#
.SYNOPSIS
    Intune Remediation - REMEDIATION (REVERT)
    Undoes Remediate-LAPSAdmin.ps1:
    1. Re-enables the built-in Administrator (RID 500)
    2. Only once (1) is verified, deletes the biadm account and its profile
    3. Triggers Windows LAPS so the built-in Administrator's password is rotated and escrowed

.NOTES
    Run as: System | 64-bit PowerShell: Yes
    Before assigning: clear "Administrator Account Name" in the "Devicie - Windows LAPS"
    policy (so LAPS manages the built-in account again) and unassign the original
    LAPS admin remediation, otherwise the two will undo each other.
#>

$AccountName = 'biadm'
$LogPath     = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-LAPSAdmin-Revert.log"

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format 's'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $Message
}

try {
    Write-Log "---- Revert started ----"

    # 1. Re-enable built-in Administrator (matched by RID 500, so renamed accounts are caught)
    $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' }
    if (-not $builtIn) { throw "Built-in Administrator (RID 500) not found" }

    if (-not $builtIn.Enabled) {
        Enable-LocalUser -SID $builtIn.SID -ErrorAction Stop
        Write-Log "Enabled built-in Administrator ($($builtIn.Name))"
    }

    # Verify before removing biadm so the device is never left without a local admin
    if (-not (Get-LocalUser -SID $builtIn.SID -ErrorAction Stop).Enabled) {
        throw "Built-in Administrator could not be enabled - $AccountName left in place"
    }

    # 2. Remove biadm and its profile
    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if ($user) {
        $sid = $user.SID.Value

        Remove-LocalUser -SID $user.SID -ErrorAction Stop
        Write-Log "Removed local account $AccountName ($sid)"

        $profile = Get-CimInstance Win32_UserProfile -Filter "SID = '$sid'" -ErrorAction SilentlyContinue
        if ($profile) {
            if ($profile.Loaded) {
                Write-Log "Profile for $AccountName is loaded - left at $($profile.LocalPath)"
            }
            else {
                Remove-CimInstance -InputObject $profile -ErrorAction Stop
                Write-Log "Removed profile $($profile.LocalPath)"
            }
        }
    }

    # 3. Rotate the built-in Administrator password through Windows LAPS
    if (Get-Command Reset-LapsPassword -ErrorAction SilentlyContinue) {
        try {
            Invoke-LapsPolicyProcessing -ErrorAction Stop
            Reset-LapsPassword -ErrorAction Stop
            Write-Log "Windows LAPS password rotated"
        }
        catch {
            # Expected if the LAPS policy still names biadm - fix the policy, LAPS rotates on next cycle
            Write-Log "LAPS rotation not forced: $($_.Exception.Message)"
        }
    }

    Write-Log "---- Revert completed ----"
    exit 0
}
catch {
    Write-Log "Revert failed: $($_.Exception.Message)"
    exit 1
}