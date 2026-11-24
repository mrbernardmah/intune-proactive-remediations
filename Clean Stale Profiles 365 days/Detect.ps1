<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects local user profiles that have not been used for more than $InactiveDays days.

.DESCRIPTION
    Exit 0 = compliant (no stale profiles)    -> remediation does not run
    Exit 1 = non-compliant (stale profiles)   -> remediation runs

    Last-use time is taken from the ProfileList registry values
    LocalProfileLoadTime*/LocalProfileUnloadTime* (Windows 10 1903+), which are far more
    reliable than Win32_UserProfile.LastUseTime (that one is bumped by AV scans, updates, etc.).
    Falls back to NTUSER.DAT LastWriteTime. Profiles with no usable timestamp are never flagged.

    Intune settings:
      Run this script using the logged-on credentials : No  (runs as SYSTEM)
      Enforce script signature check                  : No  (unless you sign it)
      Run script in 64-bit PowerShell                 : Yes

.NOTES
    Keep the CONFIG block identical in the detection and remediation scripts.
#>

#region ---------- CONFIG (keep in sync with remediation script) ----------
$InactiveDays  = 365

# Profile folder names never to remove (case-insensitive, wildcards allowed)
$ExcludedUsers = @(
    'Administrator'
    'defaultuser*'
    'DefaultAccount'
    'WDAGUtilityAccount'
    'Public'
    'Default'
)

# Also protect the last user that signed in at the logon screen
$ProtectLastLoggedOnUser = $true
#endregion -------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

function Convert-RegFileTime {
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
    # Registry DWORDs come back as signed Int32; mask to unsigned before combining
    $h  = [int64]$High -band [int64]4294967295
    $l  = [int64]$Low  -band [int64]4294967295
    $ft = ($h * [int64]4294967296) + $l
    if ($ft -le 0) { return $null }
    try { return [DateTime]::FromFileTimeUtc($ft) } catch { return $null }
}

function Get-ProfileLastUse {
    param([string]$Sid, [string]$LocalPath)

    $key   = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid"
    $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    if ($props) {
        $times = @(
            Convert-RegFileTime $props.LocalProfileLoadTimeHigh   $props.LocalProfileLoadTimeLow
            Convert-RegFileTime $props.LocalProfileUnloadTimeHigh $props.LocalProfileUnloadTimeLow
        ) | Where-Object { $_ }
        if ($times) {
            return [pscustomobject]@{ Time = ($times | Sort-Object -Descending | Select-Object -First 1); Source = 'ProfileList' }
        }
    }

    $ntUser = Join-Path $LocalPath 'NTUSER.DAT'
    $item   = Get-Item -LiteralPath $ntUser -Force -ErrorAction SilentlyContinue
    if ($item) {
        return [pscustomobject]@{ Time = $item.LastWriteTimeUtc; Source = 'NTUSER.DAT' }
    }
    return $null
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludedUsers) { if ($Name -like $pattern) { return $true } }
    return $false
}

function Get-StaleProfiles {
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)

    $lastSid = $null
    if ($ProtectLastLoggedOnUser) {
        $lastSid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI' -ErrorAction SilentlyContinue).LastLoggedOnUserSID
    }

    Get-CimInstance -ClassName Win32_UserProfile |
        Where-Object {
            -not $_.Special -and -not $_.Loaded -and
            $_.LocalPath -and
            ($_.SID -like 'S-1-5-21-*' -or $_.SID -like 'S-1-12-1-*') -and   # AD/local and Entra ID users only
            $_.SID -ne $lastSid
        } |
        ForEach-Object {
            $name = Split-Path $_.LocalPath -Leaf
            if (Test-Excluded $name) { return }

            $lastUse = Get-ProfileLastUse -Sid $_.SID -LocalPath $_.LocalPath
            if (-not $lastUse) { return }                     # no reliable timestamp -> leave it alone
            if ($lastUse.Time -ge $cutoff) { return }

            [pscustomobject]@{
                Name         = $name
                SID          = $_.SID
                LocalPath    = $_.LocalPath
                LastUseUtc   = $lastUse.Time
                Source       = $lastUse.Source
                DaysInactive = [int]((Get-Date).ToUniversalTime() - $lastUse.Time).TotalDays
                CimInstance  = $_
            }
        }
}

try {
    $stale = @(Get-StaleProfiles)
    if ($stale.Count -gt 0) {
        $list = ($stale | ForEach-Object { "$($_.Name) ($($_.DaysInactive)d)" }) -join ', '
        Write-Output "NonCompliant: $($stale.Count) profile(s) inactive > $InactiveDays days: $list"
        exit 1
    }
    Write-Output "Compliant: no profiles inactive > $InactiveDays days"
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 0   # don't trigger remediation on a detection failure
}