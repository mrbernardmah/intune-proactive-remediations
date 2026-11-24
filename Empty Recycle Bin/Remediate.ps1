#Requires -Version 5.1
<#
.SYNOPSIS
    Intune remediation: empties the Recycle Bin on every fixed drive.

.DESCRIPTION
    Running as SYSTEM, Clear-RecycleBin only empties SYSTEM's own bin, so this script works on the
    Recycle Bin folders directly: X:\$Recycle.Bin\<user SID>\ on every fixed drive.

    Each deleted item is a pair of entries:
      $Ixxxxxx  - small info file holding the original path, size and the date it was deleted
      $Rxxxxxx  - the deleted file or folder itself
    The script deletes both halves together, so the bin is never left with broken entries.
    The deletion date in the $I file drives the optional age filter. $R entries with no $I file
    can't be restored from the Recycle Bin, so they're always removed.

    Junctions/symlinks inside deleted folders are removed as links only; their targets are never touched.
    The bin's own desktop.ini is kept.

.NOTES
    Intune settings:  Run this script using the logged-on credentials = No   (runs as SYSTEM)
                      Run script in 64-bit PowerShell                  = Yes
    Log file:         C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-EmptyRecycleBin.log
    Exit codes:       0 = ran (see output for counts), 1 = unexpected script error
#>

# ---------------- Settings ----------------
$MinAgeDays        = 0       # Only delete items that have been in the bin for this many days. 0 = empty it completely.
$SignedInUsersOnly = $false  # $true = only empty the bins of users signed in right now. $false = every user's bin.
# ------------------------------------------

$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\Remediate-EmptyRecycleBin.log'
$script:Stats = @{ Items = 0; Bytes = [int64]0; Failed = 0; Bins = 0 }

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Get-LoggedOnUserSids {
    # One explorer.exe per interactive session (console, RDP, fast user switching), owned by the signed-in user.
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid } |
        Where-Object { $_ } | Sort-Object -Unique
}

function Get-RecycleBinFolders {
    $sids = @()
    if ($SignedInUsersOnly) {
        $sids = @(Get-LoggedOnUserSids)
        if ($sids.Count -eq 0) { Write-Log 'No user signed in - nothing to do'; return }
    }

    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop
    foreach ($d in $drives) {
        $root = Join-Path ($d.DeviceID + '\') '$Recycle.Bin'
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }

        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'S-1-*' -and (-not $SignedInUsersOnly -or $sids -contains $_.Name) }
    }
}

function Get-AccountName {
    param([string]$Sid)
    try { (New-Object System.Security.Principal.SecurityIdentifier $Sid).Translate([System.Security.Principal.NTAccount]).Value }
    catch { "$Sid (unknown or deleted account)" }
}

function Read-RecycleInfo {
    # $I layout (Vista and later): 8-byte version, 8-byte original size, 8-byte FILETIME of deletion, then the path.
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

function Remove-SafeItem {
    # Deletes a file or folder tree without following junctions/symlinks.
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    $strip  = [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
    $isLink = ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

    if ($Item -is [IO.DirectoryInfo] -and -not $isLink) {
        foreach ($child in $Item.GetFileSystemInfos()) { Remove-SafeItem -Item $child }
    }
    $Item.Attributes = $Item.Attributes -band (-bnot $strip)
    $Item.Delete()
}

function Clear-RecycleBinFolder {
    param([Parameter(Mandatory)][System.IO.DirectoryInfo]$Folder, [Parameter(Mandatory)][datetime]$Cutoff)

    try { $entries = $Folder.GetFileSystemInfos() }
    catch { Write-Log "  Cannot read $($Folder.FullName): $($_.Exception.Message)"; $script:Stats.Failed++; return }

    $byName = @{}                                   # PowerShell hashtables are case-insensitive
    foreach ($e in $entries) { $byName[$e.Name] = $e }
    $paired = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($info in ($entries | Where-Object { $_ -is [IO.FileInfo] -and $_.Name -like '$I*' })) {
        $rName = '$R' + $info.Name.Substring(2)
        $data  = $byName[$rName]
        [void]$paired.Add($info.Name); if ($data) { [void]$paired.Add($rName) }

        $meta      = Read-RecycleInfo -File $info
        $deletedAt = if ($meta) { $meta.DeletedAt } else { $info.LastWriteTime }
        if ($deletedAt -ge $Cutoff) { continue }

        try {
            if ($data) { Remove-SafeItem -Item $data }
            Remove-SafeItem -Item $info
            $script:Stats.Items++
            if ($meta -and $meta.Size -gt 0) { $script:Stats.Bytes += $meta.Size }
        }
        catch {
            $script:Stats.Failed++
            Write-Log "  Failed: $($info.FullName) - $($_.Exception.Message)"
        }
    }

    # $R entries with no matching $I file can't be restored - always remove them.
    foreach ($orphan in ($entries | Where-Object { $_.Name -like '$R*' -and -not $paired.Contains($_.Name) })) {
        try {
            $size = if ($orphan -is [IO.FileInfo]) { $orphan.Length } else { 0 }
            Remove-SafeItem -Item $orphan
            $script:Stats.Items++
            $script:Stats.Bytes += $size
        }
        catch {
            $script:Stats.Failed++
            Write-Log "  Failed: $($orphan.FullName) - $($_.Exception.Message)"
        }
    }
}

# ---------------- Main ----------------
try {
    try { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force -ErrorAction Stop | Out-Null } catch { }
    Write-Log '===== Remediation started ====='

    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { [datetime]::MaxValue }

    foreach ($bin in Get-RecycleBinFolders) {
        Write-Log "Emptying $($bin.FullName) [$(Get-AccountName $bin.Name)]"
        Clear-RecycleBinFolder -Folder $bin -Cutoff $cutoff
        $script:Stats.Bins++
    }

    $summary = 'Recycle Bin: {0} bin(s) processed - {1} item(s), {2:N2} GB deleted, {3} failed' -f `
        $script:Stats.Bins, $script:Stats.Items, ($script:Stats.Bytes / 1GB), $script:Stats.Failed
    Write-Log $summary
    Write-Log '===== Remediation finished ====='
    Write-Output $summary
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}