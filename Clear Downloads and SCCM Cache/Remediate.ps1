#Requires -Version 5.1
<#
.SYNOPSIS
    Intune remediation: empties every user's Downloads folder and clears the ConfigMgr client cache (ccmcache).

.DESCRIPTION
    Downloads
      - Covers only users signed in when the script runs (every interactive session, incl. RDP).
      - Follows each signed-in user's Downloads folder if it has been redirected.
      - Deletes the contents only; the Downloads folder itself and its desktop.ini are kept.
      - Junctions/symlinks are removed as links only - their targets are never touched.
      - Downloads redirected into OneDrive or to a network share are skipped by default.

    ccmcache
      - Deletes cache elements through the ConfigMgr client's own API (UIResource.UIResourceMgr),
        so the client's cache index stays consistent (deleting folders directly corrupts it).
      - Then removes folders in the cache location that the client no longer tracks.
      - Skipped cleanly if the ConfigMgr client is not installed.

.NOTES
    Intune settings:  Run this script using the logged-on credentials = No   (runs as SYSTEM)
                      Run script in 64-bit PowerShell                  = Yes
    Log file:         C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-ClearDownloadsCcmcache.log
    Exit codes:       0 = ran (see output for counts), 1 = unexpected script error
#>

# ---------------- Settings ----------------
$MinAgeDays                 = 0      # Only delete Downloads items not modified for this many days. 0 = delete everything.
$IncludePublicDownloads     = $false # Also empty C:\Users\Public\Downloads (shared, not tied to a signed-in user)
$SkipOneDriveDownloads      = $true  # Deleting inside a OneDrive-synced folder also deletes the cloud copy
$SkipNetworkDownloads       = $true  # Don't empty a Downloads folder redirected to a UNC path
$IncludePersistedCache      = $true  # Also delete ccmcache content marked "persist content in the client cache"
$RemoveOrphanedCacheFolders = $true  # Remove ccmcache folders the client no longer tracks
# ------------------------------------------

$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\Remediate-ClearDownloadsCcmcache.log'
$DownloadsGuid = '{374DE290-123F-4565-9164-39C4925E467B}'
$script:Stats = @{ Files = 0; Dirs = 0; Bytes = [int64]0; Failed = 0 }

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

function Get-DownloadsFolders {
    $results = New-Object System.Collections.Generic.List[object]

    $loggedOn = @(Get-LoggedOnUserSids)
    if ($loggedOn.Count -eq 0) { Write-Log 'Downloads: no user signed in' }

    $profiles = Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = FALSE' -ErrorAction Stop |
        Where-Object { $loggedOn -contains $_.SID -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) }

    foreach ($p in $profiles) {
        $path = Join-Path $p.LocalPath 'Downloads'

        # The user is signed in, so their hive is loaded and any Downloads redirection can be read.
        $regPath = "Registry::HKEY_USERS\$($p.SID)\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        $redirected = (Get-ItemProperty -LiteralPath $regPath -Name $DownloadsGuid -ErrorAction SilentlyContinue).$DownloadsGuid
        if ($redirected) {
            $expanded = $redirected -ireplace '%USERPROFILE%', $p.LocalPath
            if ($expanded -notmatch '%') { $path = $expanded }
        }

        $results.Add([pscustomobject]@{ Owner = (Split-Path $p.LocalPath -Leaf); Path = $path })
    }

    if ($IncludePublicDownloads) {
        $public = if ($env:PUBLIC) { $env:PUBLIC } else { Join-Path $env:SystemDrive 'Users\Public' }
        $results.Add([pscustomobject]@{ Owner = 'Public'; Path = (Join-Path $public 'Downloads') })
    }

    $results | Sort-Object Path -Unique
}

function Clear-Directory {
    param(
        [Parameter(Mandatory)][System.IO.DirectoryInfo]$Directory,
        [Parameter(Mandatory)][datetime]$Cutoff,
        [switch]$IsRoot
    )

    try { $children = $Directory.GetFileSystemInfos() }
    catch {
        Write-Log "  Cannot read $($Directory.FullName): $($_.Exception.Message)"
        $script:Stats.Failed++
        return
    }

    $stripAttrs = [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System

    foreach ($child in $children) {
        if ($IsRoot -and $child.Name -ieq 'desktop.ini') { continue }

        try {
            $isLink = ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

            if ($child -is [IO.DirectoryInfo] -and -not $isLink) {
                Clear-Directory -Directory $child -Cutoff $Cutoff
                $child.Refresh()
                $isEmpty = -not $child.EnumerateFileSystemInfos().GetEnumerator().MoveNext()
                if ($isEmpty -and $child.CreationTime -lt $Cutoff) {
                    $child.Attributes = $child.Attributes -band (-bnot $stripAttrs)
                    $child.Delete()
                    $script:Stats.Dirs++
                }
            }
            elseif ($child.LastWriteTime -lt $Cutoff) {
                # Plain files, plus file/dir symlinks and junctions (Delete() removes only the link).
                $size = if ($child -is [IO.FileInfo] -and -not $isLink) { $child.Length } else { 0 }
                $child.Attributes = $child.Attributes -band (-bnot $stripAttrs)
                $child.Delete()
                if ($child -is [IO.DirectoryInfo]) { $script:Stats.Dirs++ } else { $script:Stats.Files++ }
                $script:Stats.Bytes += $size
            }
        }
        catch {
            $script:Stats.Failed++
            Write-Log "  Failed: $($child.FullName) - $($_.Exception.Message)"
        }
    }
}

function Clear-CcmCache {
    try { $ui = New-Object -ComObject UIResource.UIResourceMgr -ErrorAction Stop }
    catch {
        Write-Log 'ccmcache: ConfigMgr client not installed - skipped'
        return 'ccmcache: skipped (no ConfigMgr client)'
    }

    $cache    = $ui.GetCacheInfo()
    $location = $cache.Location
    $elements = @($cache.GetCacheElements())
    $sizeKB   = ($elements | Measure-Object -Property ContentSize -Sum).Sum   # ContentSize is in KB
    Write-Log ("ccmcache: {0} - {1} element(s), {2:N0} MB" -f $location, $elements.Count, ($sizeKB / 1KB))

    foreach ($el in $elements) {
        try {
            if ($IncludePersistedCache) { $cache.DeleteCacheElementEx([string]$el.CacheElementID, $true) }
            else                        { $cache.DeleteCacheElement([string]$el.CacheElementID) }
            Write-Log ("  Requested delete: {0} v{1} ({2:N0} MB)" -f $el.ContentId, $el.ContentVersion, ($el.ContentSize / 1KB))
        }
        catch {
            Write-Log "  Failed: $($el.ContentId) - $($_.Exception.Message)"
        }
    }

    # Content in use by a running deployment is left alone by the client; report what's left.
    $remaining = @($cache.GetCacheElements())
    $orphans = 0

    $isUnsafeLocation = (-not $location) -or ($location -match '^[A-Za-z]:\\?$') -or
                        ($location.TrimEnd('\') -ieq $env:SystemRoot)
    if ($RemoveOrphanedCacheFolders -and -not $isUnsafeLocation -and (Test-Path -LiteralPath $location)) {
        $tracked = @($remaining | ForEach-Object { ([string]$_.Location).TrimEnd('\') })
        Get-ChildItem -LiteralPath $location -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $tracked -notcontains $_.FullName } |
            ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                    $orphans++
                    Write-Log "  Removed untracked folder: $($_.FullName)"
                }
                catch { Write-Log "  Failed untracked folder: $($_.FullName) - $($_.Exception.Message)" }
            }
    }

    $removed = $elements.Count - $remaining.Count
    Write-Log "ccmcache: removed $removed of $($elements.Count) element(s), $($remaining.Count) remaining (in use), $orphans untracked folder(s) removed"
    return "ccmcache: removed $removed/$($elements.Count), $($remaining.Count) in use, $orphans untracked folders removed"
}

# ---------------- Main ----------------
try {
    try { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force -ErrorAction Stop | Out-Null } catch { }
    Write-Log '===== Remediation started ====='

    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { [datetime]::MaxValue }
    $cleared = 0; $skipped = 0

    foreach ($dl in Get-DownloadsFolders) {
        if (-not (Test-Path -LiteralPath $dl.Path -PathType Container)) { continue }

        if ($SkipNetworkDownloads -and $dl.Path -like '\\*') {
            Write-Log "Downloads [$($dl.Owner)]: $($dl.Path) is a network path - skipped"; $skipped++; continue
        }
        if ($SkipOneDriveDownloads -and $dl.Path -like '*\OneDrive*') {
            Write-Log "Downloads [$($dl.Owner)]: $($dl.Path) is in OneDrive - skipped"; $skipped++; continue
        }

        Write-Log "Downloads [$($dl.Owner)]: clearing $($dl.Path)"
        Clear-Directory -Directory (Get-Item -LiteralPath $dl.Path -Force) -Cutoff $cutoff -IsRoot
        $cleared++
    }

    $dlSummary = 'Downloads: {0} folder(s) cleared, {1} skipped - {2} file(s), {3} folder(s), {4:N2} GB deleted, {5} failed' -f `
        $cleared, $skipped, $script:Stats.Files, $script:Stats.Dirs, ($script:Stats.Bytes / 1GB), $script:Stats.Failed
    Write-Log $dlSummary

    $ccmSummary = Clear-CcmCache

    Write-Log '===== Remediation finished ====='
    Write-Output "$dlSummary | $ccmSummary"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
