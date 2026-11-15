<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    1. Creates the Windows LAPS managed account (biadm) with a random throwaway password
    2. Enables it and adds it to the local Administrators group
    3. Only once (1) and (2) are verified, disables the built-in Administrator (RID 500)
    4. Triggers Windows LAPS so the password is rotated and escrowed straight away

.NOTES
    Run as: System | 64-bit PowerShell: Yes
    The account name must match "Administrator Account Name" in the
    "Devicie - Windows LAPS" Intune policy, otherwise LAPS will not manage it.
#>

$AccountName   = 'biadm'
$Description   = 'Windows LAPS managed local administrator'
$AdminGroupSid = 'S-1-5-32-544'
$LogPath       = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-LAPSAdmin.log"

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format 's'), $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    Write-Output $Message
}

function New-RandomPassword {
    param([int]$Length = 32)
    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',
        'abcdefghijkmnopqrstuvwxyz',
        '23456789',
        '!@#$%^&*()-_=+[]{}?'
    )
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = {
        param($chars)
        $b = New-Object byte[] 4
        $rng.GetBytes($b)
        $chars[[BitConverter]::ToUInt32($b, 0) % $chars.Length]
    }
    # Guarantee one of each character class, fill the rest, then shuffle
    $chars = @($sets | ForEach-Object { & $pick $_ })
    while ($chars.Count -lt $Length) { $chars += & $pick $all }
    -join ($chars | Sort-Object { $b = New-Object byte[] 4; $rng.GetBytes($b); [BitConverter]::ToUInt32($b, 0) })
}

function Get-AdminGroup {
    $groupName = (New-Object System.Security.Principal.SecurityIdentifier $AdminGroupSid).Translate(
        [System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
}

function Get-LocalAdminMemberSids {
    $group = Get-AdminGroup
    @($group.Invoke('Members')) | ForEach-Object {
        $sidBytes = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
    }
}

try {
    Write-Log "---- Remediation started ----"

    # 1. Create or enable biadm
    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $user) {
        # Throwaway password - Windows LAPS replaces it on the next rotation (forced below)
        $securePw = ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force
        $user = New-LocalUser -Name $AccountName -Password $securePw -Description $Description `
                    -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop
        Write-Log "Created local account $AccountName"
    }
    if (-not $user.Enabled) {
        Enable-LocalUser -SID $user.SID -ErrorAction Stop
        Write-Log "Enabled $AccountName"
    }

    # 2. Add to local Administrators
    if ((Get-LocalAdminMemberSids) -notcontains $user.SID.Value) {
        (Get-AdminGroup).Add("WinNT://$env:COMPUTERNAME/$AccountName,user")
        Write-Log "Added $AccountName to local Administrators"
    }

    # Verify before touching the built-in account so the device is never left without a local admin
    $user = Get-LocalUser -Name $AccountName -ErrorAction Stop
    if (-not $user.Enabled -or (Get-LocalAdminMemberSids) -notcontains $user.SID.Value) {
        throw "$AccountName could not be verified as an enabled local admin - built-in Administrator left untouched"
    }

    # 3. Disable built-in Administrator (matched by RID 500, so renamed accounts are caught)
    $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' }
    if ($builtIn -and $builtIn.Enabled) {
        Disable-LocalUser -SID $builtIn.SID -ErrorAction Stop
        Write-Log "Disabled built-in Administrator ($($builtIn.Name))"
    }

    # 4. Have Windows LAPS pick up the account and rotate/escrow its password now
    if (Get-Command Reset-LapsPassword -ErrorAction SilentlyContinue) {
        try {
            Invoke-LapsPolicyProcessing -ErrorAction Stop
            Reset-LapsPassword -ErrorAction Stop
            Write-Log "Windows LAPS password rotated for $AccountName"
        }
        catch {
            # Not fatal - LAPS will rotate on its next processing cycle (~1 hour)
            Write-Log "LAPS rotation not forced: $($_.Exception.Message)"
        }
    }
    else {
        Write-Log "Windows LAPS cmdlets not present - check the OS build supports Windows LAPS"
    }

    Write-Log "---- Remediation completed ----"
    exit 0
}
catch {
    Write-Log "Remediation failed: $($_.Exception.Message)"
    exit 1
}