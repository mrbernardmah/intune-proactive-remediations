#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection: flags the device if the Recycle Bin on any fixed drive holds content.

.NOTES
    Pair with Remediate-EmptyRecycleBin.ps1. Keep $MinAgeDays and $SignedInUsersOnly in step with that script.
    Intune settings:  Run this script using the logged-on credentials = No   (runs as SYSTEM)
                      Run script in 64-bit PowerShell                  = Yes
    Exit codes:       0 = compliant (nothing to clear), 1 = remediation needed
#>

# ---------------- Settings ----------------
$MinAgeDays        = 0       # Only count items that have been in the bin for this many days. 0 = anything counts.
$SignedInUsersOnly = $false  # $true = only check the bins of users signed in right now.
$ThresholdMB       = 0       # Only flag the device when qualifying items total more than this. 0 = any item.
# ------------------------------------------

function Get-LoggedOnUserSids {
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid } |
        Where-Object { $_ } | Sort-Object -Unique
}

function Get-RecycleBinFolders {
    $sids = @()
    if ($SignedInUsersOnly) {
        $sids = @(Get-LoggedOnUserSids)
        if ($sids.Count -eq 0) { return }
    }
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
    foreach ($d in $drives) {
        $root = Join-Path ($d.DeviceID + '\') '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'S-1-*' -and (-not $SignedInUsersOnly -or $sids -contains $_.Name) }
    }
}

function Read-RecycleInfo {
    param([System.IO.FileInfo]$File)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
        if ($bytes.Length -lt 24) { return $null }
        [pscustomobject]@{
            Size      = [BitConverter]::ToInt64($bytes, 8)
            DeletedAt = [DateTime]::FromFileTime([BitConverter]::ToInt64($bytes, 16))
        }
    }
    catch { $null }
}

try {
    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { [datetime]::MaxValue }
    $count = 0; $bytes = [int64]0

    foreach ($bin in Get-RecycleBinFolders) {
        $entries = @(Get-ChildItem -LiteralPath $bin.FullName -Force -ErrorAction SilentlyContinue)
        $infoNames = @{}

        foreach ($info in ($entries | Where-Object { -not $_.PSIsContainer -and $_.Name -like '$I*' })) {
            $infoNames['$R' + $info.Name.Substring(2)] = $true
            $meta = Read-RecycleInfo -File $info
            $deletedAt = if ($meta) { $meta.DeletedAt } else { $info.LastWriteTime }
            if ($deletedAt -lt $cutoff) {
                $count++
                if ($meta -and $meta.Size -gt 0) { $bytes += $meta.Size }
            }
        }

        # $R entries with no $I file are junk the remediation always removes.
        foreach ($orphan in ($entries | Where-Object { $_.Name -like '$R*' -and -not $infoNames.ContainsKey($_.Name) })) {
            $count++
            if (-not $orphan.PSIsContainer) { $bytes += $orphan.Length }
        }
    }

    $sizeMB = $bytes / 1MB
    if ($count -gt 0 -and $sizeMB -gt $ThresholdMB) {
        Write-Output ('Needs emptying: {0} item(s), {1:N0} MB in the Recycle Bin' -f $count, $sizeMB)
        exit 1
    }

    Write-Output ('Compliant: {0} qualifying item(s), {1:N0} MB in the Recycle Bin' -f $count, $sizeMB)
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}