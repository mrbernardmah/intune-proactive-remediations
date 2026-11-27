<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Google Chrome installed in USER context (per-user, %LOCALAPPDATA%).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : Yes
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Closes only the PER-USER chrome.exe processes (system-wide Chrome keeps running).
    - Keeps the user's Chrome profile (bookmarks/passwords in "User Data"), so a
      system-wide/managed Chrome picks it up. Set $DeleteProfile = $true to remove it.
    - System-wide Chrome (Program Files / HKLM) is NOT touched.
    - Log: %LOCALAPPDATA%\Temp\Remediate-UserChrome.log
#>

# Leave empty to remove ANY user-context Chrome version (must match the detection script).
$TargetVersions = @()
$DeleteProfile  = $false

$ErrorActionPreference = 'Stop'

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome'
$chromeRoot   = Join-Path $env:LOCALAPPDATA 'Google\Chrome'
$appDir       = Join-Path $chromeRoot 'Application'
$logFile      = Join-Path $env:TEMP 'Remediate-UserChrome.log'

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Get-UserChromeVersions {
    $v = @()
    if (Test-Path $uninstallKey) {
        $dv = (Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue).DisplayVersion
        if ($dv) { $v += $dv }
    }
    $exe = Join-Path $appDir 'chrome.exe'
    if (Test-Path $exe) {
        $fv = (Get-Item $exe).VersionInfo.ProductVersion
        if ($fv) { $v += $fv }
    }
    if (Test-Path $appDir) {
        $v += Get-ChildItem -Path $appDir -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
              Select-Object -ExpandProperty Name
    }
    $v | Sort-Object -Unique
}

function Stop-UserChrome {
    # Only processes running from the per-user install folder
    Get-Process -Name 'chrome', 'chrome_proxy', 'chrome_pwa_launcher', 'elevation_service' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like "$appDir\*" } |
        ForEach-Object {
            Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start remediation for $env:USERNAME ====="

    $versions = Get-UserChromeVersions
    if (-not $versions) {
        Write-Log "No user-context Chrome found. Nothing to do."
        Write-Output "No user-context Chrome found"
        exit 0
    }
    Write-Log "Found version(s): $($versions -join ', ')"

    if ($TargetVersions.Count -gt 0 -and -not ($versions | Where-Object { $TargetVersions -contains $_ })) {
        Write-Log "Installed version(s) not in target list. Nothing to do."
        Write-Output "User-context Chrome not a targeted version"
        exit 0
    }

    Stop-UserChrome

    # ---- Build list of setup.exe candidates ----
    $setupCandidates = @()
    $extraArgs = @()

    if (Test-Path $uninstallKey) {
        $us = (Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue).UninstallString
        if ($us) {
            Write-Log "UninstallString: $us"
            if ($us -match '^\s*"([^"]+)"\s*(.*)$') {
                $setupCandidates += $Matches[1]
                $extraArgs = $Matches[2] -split '\s+' | Where-Object { $_ -and $_ -notmatch '^--(uninstall|system-level|force-uninstall)$' }
            } elseif ($us -match '^\s*(\S+\.exe)\s*(.*)$') {
                $setupCandidates += $Matches[1]
                $extraArgs = $Matches[2] -split '\s+' | Where-Object { $_ -and $_ -notmatch '^--(uninstall|system-level|force-uninstall)$' }
            }
        }
    }

    if (Test-Path $appDir) {
        $setupCandidates += Get-ChildItem -Path $appDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' }
    }

    $setupCandidates = $setupCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    # ---- Run the Chrome uninstaller ----
    foreach ($setup in $setupCandidates) {
        if (-not (Get-UserChromeVersions)) { break }

        $uninstallArgs = @('--uninstall', '--force-uninstall') + $extraArgs
        if ($DeleteProfile) { $uninstallArgs += '--delete-profile' }

        Write-Log "Running: `"$setup`" $($uninstallArgs -join ' ')"
        $p = Start-Process -FilePath $setup -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
        # Chrome installer: 19 = uninstall successful, 20 = uninstall successful + profile deleted
        Write-Log "setup.exe exit code: $($p.ExitCode)"
        Start-Sleep -Seconds 3
    }

    # ---- Clean up leftovers if the uninstaller didn't (orphaned key / binaries) ----
    Stop-UserChrome

    if (Test-Path $appDir) {
        Write-Log "Removing leftover folder $appDir"
        Remove-Item -Path $appDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($DeleteProfile -and (Test-Path (Join-Path $chromeRoot 'User Data'))) {
        Write-Log "Removing user profile data"
        Remove-Item -Path (Join-Path $chromeRoot 'User Data') -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $uninstallKey) {
        Write-Log "Removing leftover uninstall key"
        Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Shortcuts that point at the per-user chrome.exe
    $shell = New-Object -ComObject WScript.Shell
    $shortcutLocations = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    foreach ($loc in $shortcutLocations) {
        if (-not (Test-Path $loc)) { continue }
        Get-ChildItem -Path $loc -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $target = $shell.CreateShortcut($_.FullName).TargetPath
                if ($target -and $target -like "$appDir\*") {
                    Write-Log "Removing shortcut $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }

    # ---- Verify ----
    $remaining = Get-UserChromeVersions
    if ($remaining) {
        Write-Log "FAILED: still present: $($remaining -join ', ')"
        Write-Output "Failed: user-context Chrome still present ($($remaining -join ', '))"
        exit 1
    }

    Write-Log "SUCCESS: user-context Chrome removed"
    Write-Output "Success: user-context Chrome removed for $env:USERNAME (was $($versions -join ', '))"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}