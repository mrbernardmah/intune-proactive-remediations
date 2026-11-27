<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Google Chrome installed in SYSTEM context (Program Files / HKLM).
    Handles both Chrome Enterprise MSI installs and EXE (setup.exe --system-level) installs.

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Closes ALL Chrome windows running from Program Files (all users on the device).
    - Per-user Chrome installs (%LOCALAPPDATA%) and user profiles are NOT touched.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-SystemChrome.log
#>

# Versions to remove. Empty = ANY system-context Chrome version.
# Must match the detection script.
$TargetVersions = @('149.0.7827.102')

$ErrorActionPreference = 'Stop'

$logDir  = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-SystemChrome.log'

$appDirs = @(
    "$env:ProgramFiles\Google\Chrome\Application",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application"
) | Select-Object -Unique

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Write-Log {
    param([string]$Message)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Get-SystemChromeVersions {
    $v = @()
    foreach ($dir in $appDirs) {
        if (-not (Test-Path $dir)) { continue }
        $exe = Join-Path $dir 'chrome.exe'
        if (Test-Path $exe) {
            $fv = (Get-Item $exe).VersionInfo.ProductVersion
            if ($fv) { $v += $fv }
        }
        $v += Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
              Select-Object -ExpandProperty Name
    }
    foreach ($root in $uninstallRoots) {
        $k = Join-Path $root 'Google Chrome'
        if (Test-Path $k) {
            $dv = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).DisplayVersion
            if ($dv) { $v += $dv }
        }
    }
    $v | Sort-Object -Unique
}

function Stop-SystemChrome {
    Get-Process -Name 'chrome', 'chrome_proxy', 'chrome_pwa_launcher', 'elevation_service', 'notification_helper' -ErrorAction SilentlyContinue |
        Where-Object {
            $p = $_.Path
            $p -and ($appDirs | Where-Object { $p -like "$_\*" })
        } |
        ForEach-Object {
            Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start system-context Chrome remediation ====="

    $versions = Get-SystemChromeVersions
    if (-not $versions) {
        Write-Log "No system-context Chrome found. Nothing to do."
        Write-Output "No system-context Chrome found"
        exit 0
    }
    Write-Log "Found version(s): $($versions -join ', ')"

    if ($TargetVersions.Count -gt 0 -and -not ($versions | Where-Object { $TargetVersions -contains $_ })) {
        Write-Log "Installed version(s) not in target list. Nothing to do."
        Write-Output "System Chrome present but not a targeted version ($($versions -join ', '))"
        exit 0
    }

    Stop-SystemChrome

    # ---- 1. MSI installs (Chrome Enterprise) ----
    $msiProducts = foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -eq 'Google Chrome' -and $p.WindowsInstaller -eq 1 -and $_.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
                $_.PSChildName
            }
        }
    }
    $msiProducts = $msiProducts | Select-Object -Unique

    foreach ($code in $msiProducts) {
        $msiLog = Join-Path $logDir "Chrome-MSI-Uninstall-$($code.Trim('{}')).log"
        Write-Log "Uninstalling MSI $code"
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
             -ArgumentList "/x $code /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
        Write-Log "msiexec exit code: $($p.ExitCode)  (0/3010 = success, 1605 = not installed)"
        Start-Sleep -Seconds 3
    }

    # ---- 2. EXE installs (setup.exe --system-level), or leftovers after MSI ----
    if (Get-SystemChromeVersions) {
        Stop-SystemChrome

        $setupCandidates = @()
        foreach ($root in $uninstallRoots) {
            $k = Join-Path $root 'Google Chrome'
            if (Test-Path $k) {
                $us = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).UninstallString
                if ($us) {
                    Write-Log "UninstallString: $us"
                    if ($us -match '^\s*"([^"]+setup\.exe)"') { $setupCandidates += $Matches[1] }
                    elseif ($us -match '^\s*(\S+setup\.exe)') { $setupCandidates += $Matches[1] }
                }
            }
        }
        foreach ($dir in $appDirs) {
            if (-not (Test-Path $dir)) { continue }
            $setupCandidates += Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                Sort-Object { [version]$_.Name } -Descending |
                ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' }
        }
        $setupCandidates = $setupCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

        foreach ($setup in $setupCandidates) {
            if (-not (Get-SystemChromeVersions)) { break }
            $uninstallArgs = @('--uninstall', '--system-level', '--force-uninstall')
            Write-Log "Running: `"$setup`" $($uninstallArgs -join ' ')"
            $p = Start-Process -FilePath $setup -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
            # Chrome installer: 19 = uninstall successful
            Write-Log "setup.exe exit code: $($p.ExitCode)"
            Start-Sleep -Seconds 3
        }
    }

    # ---- 3. Clean up leftovers (orphaned folder / uninstall key / shortcuts) ----
    Stop-SystemChrome
    foreach ($dir in $appDirs) {
        if (Test-Path $dir) {
            Write-Log "Removing leftover folder $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($root in $uninstallRoots) {
        $k = Join-Path $root 'Google Chrome'
        if (Test-Path $k) {
            Write-Log "Removing leftover uninstall key $k"
            Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcutLocations = @(
        "$env:PUBLIC\Desktop",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
    )
    foreach ($loc in $shortcutLocations) {
        if (-not (Test-Path $loc)) { continue }
        Get-ChildItem -Path $loc -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $target = $shell.CreateShortcut($_.FullName).TargetPath
                if ($target -and ($appDirs | Where-Object { $target -like "$_\*" })) {
                    Write-Log "Removing shortcut $($_.FullName)"
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }

    # ---- Verify ----
    $remaining = Get-SystemChromeVersions
    if ($remaining) {
        Write-Log "FAILED: still present: $($remaining -join ', ')"
        Write-Output "Failed: system-context Chrome still present ($($remaining -join ', '))"
        exit 1
    }

    Write-Log "SUCCESS: system-context Chrome removed"
    Write-Output "Success: system-context Chrome removed (was $($versions -join ', '))"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}