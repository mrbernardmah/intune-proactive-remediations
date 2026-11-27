<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls 7-Zip (system context) at the targeted version(s).
    Handles both MSI ("7-Zip 15.14 (x64 edition)") and EXE ("7-Zip 15.14 (x64)") installs.

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Closes running 7-Zip windows (7zFM / 7zG / 7z) started from the install folder.
    - 7-zip.dll is a shell extension loaded by Explorer, so it may stay on disk until
      the next reboot. The script does NOT restart Explorer or reboot.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-7Zip.log
#>

# Versions to remove. Empty = ANY 7-Zip version. Must match the detection script.
$TargetVersions = @('15.14')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-7Zip.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$installDirs = @("$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip") | Select-Object -Unique

function Write-Log([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function Test-TargetVersion([string]$Version) {
    if (-not $Version) { return $false }
    if ($TargetVersions.Count -eq 0) { return $true }
    foreach ($t in $TargetVersions) {
        if ($Version -eq $t -or $Version -like "$t.*") { return $true }
    }
    return $false
}

function Get-7ZipEntries {
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like '7-Zip*' -and (Test-TargetVersion $p.DisplayVersion)) {
                [pscustomobject]@{
                    KeyPath          = $_.PSPath
                    KeyName          = $_.PSChildName
                    DisplayName      = $p.DisplayName
                    DisplayVersion   = $p.DisplayVersion
                    UninstallString  = $p.UninstallString
                    InstallLocation  = $p.InstallLocation
                    WindowsInstaller = $p.WindowsInstaller
                }
            }
        }
    }
}

function Get-7ZipTargetExes {
    foreach ($dir in $installDirs) {
        $exe = Join-Path $dir '7z.exe'
        if ((Test-Path $exe) -and (Test-TargetVersion ((Get-Item $exe).VersionInfo.ProductVersion -replace '\s', ''))) { $exe }
    }
}

function Stop-7Zip {
    Get-Process -Name '7zFM', '7zG', '7z' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like '*\7-Zip\*' } |
        ForEach-Object {
            Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start 7-Zip remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-7ZipEntries)
    $exes    = @(Get-7ZipTargetExes)

    if (-not $entries -and -not $exes) {
        Write-Log "Targeted 7-Zip not found. Nothing to do."
        Write-Output "Targeted 7-Zip not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    if (-not $removedNames) { $removedNames = $exes -join '; ' }
    Write-Log "Found: $removedNames"

    Stop-7Zip
    $rebootNeeded = $false

    foreach ($e in $entries) {
        if ($e.WindowsInstaller -eq 1 -and $e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
            # ---- MSI install: "7-Zip xx.xx (x64 edition)" ----
            $msiLog = Join-Path $logDir "7Zip-MSI-Uninstall-$($e.KeyName.Trim('{}')).log"
            Write-Log "Uninstalling MSI $($e.KeyName) ($($e.DisplayName))"
            $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                 -ArgumentList "/x $($e.KeyName) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
            Write-Log "msiexec exit code: $($p.ExitCode)  (0 = success, 3010 = success/reboot pending, 1605 = not installed)"
            if ($p.ExitCode -eq 3010) { $rebootNeeded = $true }
        }
        else {
            # ---- EXE install: "7-Zip xx.xx (x64)" -> Uninstall.exe /S ----
            $uninstaller = $null
            if ($e.UninstallString -match '^\s*"([^"]+\.exe)"') { $uninstaller = $Matches[1] }
            elseif ($e.UninstallString -match '^\s*(\S+\.exe)') { $uninstaller = $Matches[1] }
            if (-not $uninstaller -or -not (Test-Path $uninstaller)) {
                $dir = if ($e.InstallLocation) { $e.InstallLocation.TrimEnd('\') } else { "$env:ProgramFiles\7-Zip" }
                $uninstaller = "$dir\Uninstall.exe"
            }

            if (Test-Path $uninstaller) {
                Write-Log "Running: `"$uninstaller`" /S"
                $p = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
                Write-Log "Uninstaller exit code: $($p.ExitCode)"
                # Give the uninstaller time to finish in case it hands off to a child process
                for ($i = 0; $i -lt 30 -and (Test-Path $e.KeyPath); $i++) { Start-Sleep -Seconds 2 }
            }
            else {
                Write-Log "No uninstaller found for $($e.DisplayName); will clean up manually"
            }
        }
        Start-Sleep -Seconds 3
    }

    # ---- Clean up leftovers ----
    Stop-7Zip
    foreach ($dir in $installDirs) {
        if (-not (Test-Path $dir)) { continue }
        $exe = Join-Path $dir '7z.exe'
        $isTarget = (Test-Path $exe) -and (Test-TargetVersion ((Get-Item $exe).VersionInfo.ProductVersion -replace '\s', ''))
        if ($isTarget -or -not (Test-Path $exe)) {
            Write-Log "Removing leftover folder $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $dir) {
                # Typically 7-zip.dll held by Explorer - gone after reboot
                Write-Log "Some files in $dir are locked (likely 7-zip.dll in Explorer); they will clear after reboot"
                $rebootNeeded = $true
            }
        }
    }
    foreach ($e in @(Get-7ZipEntries)) {
        if ($e.WindowsInstaller -ne 1) {
            Write-Log "Removing orphaned uninstall key $($e.KeyName)"
            Remove-Item -Path $e.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $startMenu = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\7-Zip"
    if (Test-Path $startMenu) {
        Write-Log "Removing Start Menu folder $startMenu"
        Remove-Item -Path $startMenu -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- Verify (registry entry + 7z.exe; a locked shell DLL alone doesn't count) ----
    $remaining = @(Get-7ZipEntries) + @(Get-7ZipTargetExes)
    if ($remaining.Count -gt 0) {
        Write-Log "FAILED: 7-Zip still present"
        Write-Output "Failed: targeted 7-Zip still present"
        exit 1
    }

    $msg = "Success: removed $removedNames"
    if ($rebootNeeded) { $msg += " (reboot pending to release shell extension)" }
    Write-Log $msg
    Write-Output $msg
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}