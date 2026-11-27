<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls system-context (all-users) Python at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Order of operations per version:
      1. Stop python.exe / pythonw.exe running FROM that version's install folder only.
      2. Uninstall the bundle ("Python X.Y.Z (64-bit)") via its cached installer:
         <BundleCachePath> /uninstall /quiet /norestart /log ...
      3. Remove any remaining component MSIs for that version, e.g.
           Python 3.12.2 Add to Path / Core Interpreter / Development Libraries /
           Documentation / Executables / pip Bootstrap / Standard Library /
           Tcl/Tk Support / Test Suite / Utility Scripts  (64-bit or 32-bit)
         with msiexec /x {GUID} IGNOREDEPENDENCIES=ALL. The python.org MSIs record the
         bundle as a dependent; if the bundle is broken or already gone, a plain
         msiexec /x is blocked and the components are left behind.
         - 1618 (another install running) is retried up to 3 times.
         - 1605 (MSI no longer registered) -> the orphaned Apps & Features entry is removed.
      4. Remove the leftover install folder (usually just pip-installed site-packages)
         once python.exe is gone.

    "Python Launcher" (C:\Windows\py.exe) is shared by all versions and is kept.
    Per-user Python installs (HKCU, %LOCALAPPDATA%\Programs\Python) are not touched.
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-Python.log
#>

# Versions to remove (X.Y.Z). Must match the detection script.
$TargetVersions = @('3.12.13', '3.12.2', '3.14.7', '3.5.1')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-Python.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$pythonCoreRoots = @('HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')

function Write-Log([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Get-PythonVersionFromName([string]$Name) {
    if ($Name -match '^Python (\d+\.\d+\.\d+)\b' -and $Name -notmatch '^Python (Launcher|Install Manager)') {
        return $Matches[1]
    }
    return $null
}

function Get-PythonEntries([string]$Version) {
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            $v = Get-PythonVersionFromName $p.DisplayName
            if ($v -and $v -eq $Version) {
                [pscustomobject]@{
                    KeyPath          = $_.PSPath
                    KeyName          = $_.PSChildName
                    DisplayName      = $p.DisplayName
                    DisplayVersion   = $p.DisplayVersion
                    BundleCachePath  = $p.BundleCachePath
                    UninstallString  = $p.UninstallString
                    WindowsInstaller = $p.WindowsInstaller
                    SystemComponent  = $p.SystemComponent
                    IsBundle         = [bool]$p.BundleCachePath
                }
            }
        }
    }
}

function Get-PythonInstallDirs([string]$Version) {
    foreach ($pc in $pythonCoreRoots) {
        Get-ChildItem -Path $pc -ErrorAction SilentlyContinue | ForEach-Object {
            $ver = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Version
            if ($ver -eq $Version) {
                $ip = Get-ItemProperty -Path (Join-Path $_.PSPath 'InstallPath') -ErrorAction SilentlyContinue
                if ($ip.'(default)') { $ip.'(default)'.TrimEnd('\') }
                elseif ($ip.ExecutablePath) { Split-Path $ip.ExecutablePath -Parent }
            }
        }
    }
}

function Stop-PythonIn([string[]]$Dirs) {
    if (-not $Dirs) { return }
    Get-Process -Name 'python', 'pythonw', 'python3*' -ErrorAction SilentlyContinue | Where-Object {
        $p = $_.Path
        $p -and ($Dirs | Where-Object { $p -like "$_\*" })
    } | ForEach-Object {
        Write-Log "Stopping process $($_.Name) (PID $($_.Id)) $($_.Path)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Invoke-Msi([string]$Code, [string]$Label) {
    $msiLog = Join-Path $logDir "Python-MSI-Uninstall-$($Code.Trim('{}')).log"
    $rc = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Log "  msiexec /x $Code IGNOREDEPENDENCIES=ALL ($Label) - attempt $attempt"
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
             -ArgumentList "/x $Code IGNOREDEPENDENCIES=ALL /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
        $rc = $p.ExitCode
        Write-Log "  msiexec exit code: $rc  (0 = ok, 3010/1641 = reboot, 1605 = not registered, 1618 = busy, 1603 = fatal)"
        if ($rc -ne 1618) { break }
        Start-Sleep -Seconds 30
    }
    return $rc
}

try {
    Write-Log "===== Start Python remediation (target: $($TargetVersions -join ', ')) ====="

    $rebootNeeded = $false
    $removed = @()
    $failed  = @()

    foreach ($ver in $TargetVersions) {
        $entries = @(Get-PythonEntries $ver)
        $dirs    = @(Get-PythonInstallDirs $ver)

        if (-not $entries -and -not $dirs) { continue }
        Write-Log "--- Python $ver : $($entries.Count) registry entr(y/ies), install dir(s): $($dirs -join ', ')"

        Stop-PythonIn $dirs

        # ---- 1. Bundle uninstall ----
        foreach ($b in ($entries | Where-Object { $_.IsBundle })) {
            if (Test-Path $b.BundleCachePath) {
                $bundleLog = Join-Path $logDir "Python-$ver-Bundle-Uninstall.log"
                Write-Log "  Running: `"$($b.BundleCachePath)`" /uninstall /quiet /norestart  ($($b.DisplayName))"
                $p = Start-Process -FilePath $b.BundleCachePath `
                     -ArgumentList '/uninstall', '/quiet', '/norestart', '/log', "`"$bundleLog`"" -Wait -PassThru -WindowStyle Hidden
                Write-Log "  Bundle exit code: $($p.ExitCode)  (0 = success, 3010/1641 = reboot needed)"
                if ($p.ExitCode -in 3010, 1641) { $rebootNeeded = $true }
                Start-Sleep -Seconds 3
            }
            else {
                Write-Log "  Bundle cache missing: $($b.BundleCachePath) - falling back to component MSIs"
            }
        }

        # ---- 2. Fallback: remaining component MSIs for this version ----
        foreach ($c in (@(Get-PythonEntries $ver) | Where-Object { -not $_.IsBundle })) {
            $code = $null
            if ($c.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $c.KeyName }
            elseif ($c.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') { $code = $Matches[1] }
            if ($code) {
                $rc = Invoke-Msi $code $c.DisplayName
                if ($rc -in 3010, 1641) { $rebootNeeded = $true }
                if ($rc -eq 1605 -and (Test-Path $c.KeyPath)) {
                    # Windows Installer no longer knows this product - only the ARP entry is left
                    Write-Log "  Removing orphaned Apps & Features entry $($c.KeyName) ($($c.DisplayName))"
                    Remove-Item -Path $c.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                Write-Log "  Not an MSI, cannot remove silently: $($c.DisplayName) | $($c.UninstallString)"
            }
        }

        # ---- 3. Orphaned bundle entry (cache gone, components now removed) ----
        foreach ($b in (@(Get-PythonEntries $ver) | Where-Object { $_.IsBundle -and -not (Test-Path $_.BundleCachePath) })) {
            Write-Log "  Removing orphaned bundle entry $($b.KeyName) ($($b.DisplayName))"
            Remove-Item -Path $b.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        # ---- 4. Leftover install folder (site-packages etc.) ----
        foreach ($d in $dirs) {
            if ((Test-Path $d) -and -not (Test-Path (Join-Path $d 'python.exe'))) {
                Write-Log "  Removing leftover folder $d"
                Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (@(Get-PythonEntries $ver).Count -gt 0 -or @(Get-PythonInstallDirs $ver | Where-Object { Test-Path (Join-Path $_ 'python.exe') }).Count -gt 0) {
            Write-Log "  FAILED: Python $ver still present"
            $failed += $ver
        }
        else {
            Write-Log "  Python $ver removed"
            $removed += $ver
        }
    }

    if (-not $removed -and -not $failed) {
        Write-Log "No targeted Python versions found. Nothing to do."
        Write-Output "Targeted Python version(s) not found"
        exit 0
    }

    if ($failed) {
        Write-Output "Failed: still present $($failed -join ', ') | removed: $($removed -join ', ') - see $logFile"
        exit 1
    }

    $msg = "Success: removed Python $($removed -join ', ')"
    if ($rebootNeeded) { $msg += " (reboot pending)" }
    Write-Log $msg
    Write-Output $msg
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}