<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Removes local user profiles that have not been used for more than $InactiveDays days.

.DESCRIPTION
    Profiles are removed via Win32_UserProfile (Remove-CimInstance), which deletes both the
    profile folder and its ProfileList registry key cleanly - never delete C:\Users\<x> by hand.

    Never removed:
      - Loaded (signed-in) profiles, special/system profiles, non-user SIDs
      - Names in $ExcludedUsers
      - The last user who signed in at the logon screen (if $ProtectLastLoggedOnUser)
      - Profiles with no reliable last-use timestamp

    Log: %ProgramData%\Microsoft\IntuneManagementExtension\Logs\StaleProfileCleanup.log
         (picked up by Intune "Collect diagnostics")

    Set $WhatIf = $true for a first pilot run: it logs what would be removed and deletes nothing.

.NOTES
    Keep the CONFIG block identical in the detection and remediation scripts.
#>

#region ---------- CONFIG (keep in sync with detection script) ----------
$InactiveDays  = 365

$ExcludedUsers = @(
    'Administrator'
    'defaultuser*'
    'DefaultAccount'
    'WDAGUtilityAccount'
    'Public'
    'Default'
)

$ProtectLastLoggedOnUser = $true

# Remediation-only settings
$WhatIf             = $false   # $true = log only, delete nothing
$MaxDeletionsPerRun = 25       # safety cap; remaining profiles are handled on the next run
#endregion -------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\StaleProfileCleanup.log'

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $dir = Split-Path $LogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Simple rollover at 2 MB
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 2MB) {
            Move-Item $LogFile "$LogFile.old" -Force
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
}

function Convert-RegFileTime {
    param($High, $Low)
    if ($null -eq $High -or $null -eq $Low) { return $null }
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
            ($_.SID -like 'S-1-5-21-*' -or $_.SID -like 'S-1-12-1-*') -and
            $_.SID -ne $lastSid
        } |
        ForEach-Object {
            $name = Split-Path $_.LocalPath -Leaf
            if (Test-Excluded $name) { return }

            $lastUse = Get-ProfileLastUse -Sid $_.SID -LocalPath $_.LocalPath
            if (-not $lastUse) {
                Write-Log "Skipping $name ($($_.SID)): no reliable last-use timestamp" 'WARN'
                return
            }
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

# ---------------------------------- Main ----------------------------------
Write-Log "===== Run started (InactiveDays=$InactiveDays, WhatIf=$WhatIf, Max=$MaxDeletionsPerRun) ====="

try {
    $stale = @(Get-StaleProfiles | Sort-Object LastUseUtc)
}
catch {
    Write-Log "Failed to enumerate profiles: $($_.Exception.Message)" 'ERROR'
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}

if ($stale.Count -eq 0) {
    Write-Log 'No stale profiles found.'
    Write-Output 'No stale profiles found'
    exit 0
}

$removed = New-Object System.Collections.Generic.List[string]
$failed  = New-Object System.Collections.Generic.List[string]
$batch   = $stale | Select-Object -First $MaxDeletionsPerRun

foreach ($p in $batch) {
    $desc = "$($p.Name) [$($p.SID)] $($p.LocalPath) last used $($p.LastUseUtc.ToString('yyyy-MM-dd')) UTC ($($p.DaysInactive)d, via $($p.Source))"

    if ($WhatIf) {
        Write-Log "WHATIF would remove: $desc"
        $removed.Add($p.Name)
        continue
    }

    try {
        # Re-check it hasn't been loaded since enumeration
        $fresh = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($p.SID)'"
        if (-not $fresh) { Write-Log "Already gone: $desc"; continue }
        if ($fresh.Loaded) { Write-Log "Skipped, now loaded: $desc" 'WARN'; continue }

        Remove-CimInstance -InputObject $fresh
        Write-Log "Removed: $desc"
        $removed.Add($p.Name)
    }
    catch {
        Write-Log "FAILED to remove: $desc :: $($_.Exception.Message)" 'ERROR'
        $failed.Add($p.Name)
    }
}

$deferred = $stale.Count - @($batch).Count
$verb     = if ($WhatIf) { 'Would remove' } else { 'Removed' }
$summary  = "$verb $($removed.Count): $($removed -join ', ')"
if ($failed.Count) { $summary += " | Failed $($failed.Count): $($failed -join ', ')" }
if ($deferred -gt 0) { $summary += " | Deferred to next run: $deferred" }

Write-Log $summary
Write-Log '===== Run finished ====='
Write-Output $summary

if ($failed.Count -gt 0) { exit 1 } else { exit 0 }