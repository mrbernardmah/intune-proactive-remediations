#Requires -Version 5.1
<#
.SYNOPSIS
    Intune detection: flags the device if a signed-in user's Downloads folder has content or the ccmcache holds content.

.NOTES
    Pair with Remediate-ClearDownloadsCcmcache.ps1. Keep the settings below in step with that script.
    Intune settings:  Run this script using the logged-on credentials = No   (runs as SYSTEM)
                      Run script in 64-bit PowerShell                  = Yes
    Exit codes:       0 = compliant (nothing to clear), 1 = remediation needed
#>

# ---------------- Settings ----------------
$MinAgeDays             = 0      # Only count Downloads items not modified for this many days. 0 = anything counts.
$IncludePublicDownloads = $false
$SkipOneDriveDownloads  = $true
$SkipNetworkDownloads   = $true
$CcmCacheThresholdMB    = 0      # Flag ccmcache only when its content exceeds this size. 0 = any content.
# ------------------------------------------

$DownloadsGuid = '{374DE290-123F-4565-9164-39C4925E467B}'

function Get-LoggedOnUserSids {
    # One explorer.exe per interactive session (console, RDP, fast user switching), owned by the signed-in user.
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction SilentlyContinue).Sid } |
        Where-Object { $_ } | Sort-Object -Unique
}

function Get-DownloadsFolders {
    $results = New-Object System.Collections.Generic.List[object]

    $loggedOn = @(Get-LoggedOnUserSids)
    $profiles = Get-CimInstance -ClassName Win32_UserProfile -Filter 'Special = FALSE' -ErrorAction Stop |
        Where-Object { $loggedOn -contains $_.SID -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) }

    foreach ($p in $profiles) {
        $path = Join-Path $p.LocalPath 'Downloads'
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

try {
    $findings = New-Object System.Collections.Generic.List[string]
    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { [datetime]::MaxValue }

    # --- Downloads ---
    foreach ($dl in Get-DownloadsFolders) {
        if (-not (Test-Path -LiteralPath $dl.Path -PathType Container)) { continue }
        if ($SkipNetworkDownloads  -and $dl.Path -like '\\*')          { continue }
        if ($SkipOneDriveDownloads -and $dl.Path -like '*\OneDrive*')  { continue }

        if ($MinAgeDays -le 0) {
            $hit = Get-ChildItem -LiteralPath $dl.Path -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ine 'desktop.ini' } | Select-Object -First 1
        }
        else {
            $hit = Get-ChildItem -LiteralPath $dl.Path -Force -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff -and
                               -not ($_.Name -ieq 'desktop.ini' -and $_.DirectoryName -ieq $dl.Path) } |
                Select-Object -First 1
        }
        if ($hit) { $findings.Add("Downloads[$($dl.Owner)]") }
    }

    # --- ccmcache ---
    try {
        $ui = New-Object -ComObject UIResource.UIResourceMgr -ErrorAction Stop
        $elements = @($ui.GetCacheInfo().GetCacheElements())
        $sizeMB = (($elements | Measure-Object -Property ContentSize -Sum).Sum) / 1KB   # ContentSize is in KB
        if ($elements.Count -gt 0 -and $sizeMB -gt $CcmCacheThresholdMB) {
            $findings.Add(('ccmcache[{0} items, {1:N0} MB]' -f $elements.Count, $sizeMB))
        }
    }
    catch { }   # No ConfigMgr client - nothing to check

    if ($findings.Count -gt 0) {
        Write-Output ("Needs clearing: " + ($findings -join ', '))
        exit 1
    }

    Write-Output 'Compliant: Downloads empty and ccmcache clear'
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}