<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Checks that the Windows LAPS managed account (biadm) exists, is enabled and is a
    local administrator, and that the built-in Administrator (RID 500) is disabled.

.NOTES
    Run as: System | 64-bit PowerShell: Yes | Signature check: as per your policy
    Exit 0 = compliant, Exit 1 = run remediation
#>

$AccountName   = 'biadm'          # Must match "Administrator Account Name" in the Devicie - Windows LAPS policy
$AdminGroupSid = 'S-1-5-32-544'   # BUILTIN\Administrators (language independent)

function Get-LocalAdminMemberSids {
    $groupName = (New-Object System.Security.Principal.SecurityIdentifier $AdminGroupSid).Translate(
        [System.Security.Principal.NTAccount]).Value.Split('\')[-1]
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
    # ADSI is used instead of Get-LocalGroupMember, which errors on orphaned / Entra ID SIDs
    @($group.Invoke('Members')) | ForEach-Object {
        $sidBytes = $_.GetType().InvokeMember('objectSid', 'GetProperty', $null, $_, $null)
        (New-Object System.Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
    }
}

try {
    $issues = @()

    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $user) {
        $issues += "$AccountName does not exist"
    }
    else {
        if (-not $user.Enabled) { $issues += "$AccountName is disabled" }
        if ((Get-LocalAdminMemberSids) -notcontains $user.SID.Value) {
            $issues += "$AccountName is not in local Administrators"
        }
    }

    $builtIn = Get-LocalUser | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' }
    if ($builtIn -and $builtIn.Enabled) {
        $issues += "Built-in Administrator ($($builtIn.Name)) is enabled"
    }

    if ($issues.Count -gt 0) {
        Write-Output ("Non-compliant: " + ($issues -join '; '))
        exit 1
    }

    Write-Output "Compliant: $AccountName is an enabled local admin and built-in Administrator is disabled"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}