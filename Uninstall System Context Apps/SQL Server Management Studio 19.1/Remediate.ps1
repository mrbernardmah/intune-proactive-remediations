<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Microsoft SQL Server Management Studio (system context).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    SSMS 19.x is installed by a setup bundle (SSMS-Setup-ENU.exe) that also installs
    many hidden component MSIs. The script uninstalls through the cached bundle
    (C:\ProgramData\Package Cache\{GUID}\SSMS-Setup-ENU.exe /uninstall /quiet /norestart),
    which removes SSMS and its components in the right order.

    - Closes running SSMS (Ssms.exe) windows.
    - Shared prerequisites (VC++ runtimes, ODBC / OLE DB drivers) are left in place if
      other software still uses them - this is the bundle's own behaviour.
    - Uninstall can take 5-15 minutes.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-SSMS.log
#>

# DisplayNames to remove. Must match the detection script.
$TargetDisplayNames = @('Microsoft SQL Server Management Studio - 19.1')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-SSMS.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Write-Log([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Get-SSMSEntries {
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or $p.SystemComponent -eq 1) { return }
            foreach ($t in $TargetDisplayNames) {
                if ($p.DisplayName -like $t) {
                    [pscustomobject]@{
                        KeyPath              = $_.PSPath
                        KeyName              = $_.PSChildName
                        DisplayName          = $p.DisplayName
                        DisplayVersion       = $p.DisplayVersion
                        BundleCachePath      = $p.BundleCachePath
                        QuietUninstallString = $p.QuietUninstallString
                        UninstallString      = $p.UninstallString
                        WindowsInstaller     = $p.WindowsInstaller
                    }
                    break
                }
            }
        }
    }
}

function Stop-SSMS {
    Get-Process -Name 'Ssms', 'SsmsMin' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start SSMS remediation (target: $($TargetDisplayNames -join ', ')) ====="

    $entries = @(Get-SSMSEntries)
    if (-not $entries) {
        Write-Log "Targeted SSMS not found. Nothing to do."
        Write-Output "Targeted SSMS not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    Write-Log "Found: $removedNames"

    Stop-SSMS
    $rebootNeeded = $false

    foreach ($e in $entries) {
        if ($e.WindowsInstaller -eq 1 -and $e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
            # ---- Plain MSI entry (unusual for SSMS, handled just in case) ----
            $msiLog = Join-Path $logDir "SSMS-MSI-Uninstall-$($e.KeyName.Trim('{}')).log"
            Write-Log "Uninstalling MSI $($e.KeyName) ($($e.DisplayName))"
            $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                 -ArgumentList "/x $($e.KeyName) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
            Write-Log "msiexec exit code: $($p.ExitCode)"
            if ($p.ExitCode -in 3010, 1641) { $rebootNeeded = $true }
            continue
        }

        # ---- Setup bundle (normal SSMS install) ----
        $bundleExe = $null
        if ($e.BundleCachePath -and (Test-Path $e.BundleCachePath)) {
            $bundleExe = $e.BundleCachePath
        }
        elseif ($e.UninstallString -match '^\s*"([^"]+\.exe)"' -and (Test-Path $Matches[1])) {
            $bundleExe = $Matches[1]
        }

        if (-not $bundleExe) {
            Write-Log "Cached setup bundle not found for $($e.DisplayName) (BundleCachePath: $($e.BundleCachePath)). Cannot uninstall silently."
            continue
        }

        $bundleLog = Join-Path $logDir "SSMS-Uninstall-$($e.KeyName.Trim('{}')).log"
        $uninstallArgs = @('/uninstall', '/quiet', '/norestart', '/log', "`"$bundleLog`"")
        Write-Log "Running: `"$bundleExe`" $($uninstallArgs -join ' ')"
        $p = Start-Process -FilePath $bundleExe -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
        Write-Log "Bundle exit code: $($p.ExitCode)  (0 = success, 3010/1641 = success, reboot needed)"
        if ($p.ExitCode -in 3010, 1641) { $rebootNeeded = $true }
        Start-Sleep -Seconds 5
    }

    # ---- Clean up Start Menu leftovers ----
    foreach ($lnk in Get-ChildItem -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter 'SQL Server Management Studio*.lnk' -ErrorAction SilentlyContinue) {
        if (-not (Test-Path ((New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName).TargetPath))) {
            Write-Log "Removing dead shortcut $($lnk.FullName)"
            Remove-Item -Path $lnk.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- Verify ----
    if (@(Get-SSMSEntries).Count -gt 0) {
        Write-Log "FAILED: SSMS still present"
        Write-Output "Failed: targeted SSMS still present - see $logFile"
        exit 1
    }

    $msg = "Success: removed $removedNames"
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