<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Cisco Jabber (system context, MSI) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Closes running Jabber processes (all signed-in users) before uninstalling.
    - Outlook is NOT closed. If the Jabber Outlook add-in is loaded, some files are
      removed at next reboot (msiexec returns 3010 -> reported as success, reboot pending).
    - Per-user Jabber data (%APPDATA% / %LOCALAPPDATA%\Cisco\Unified Communications\Jabber)
      is left in place.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-CiscoJabber.log
#>

# Versions to remove. Empty = ANY version. Must match the detection script.
$TargetVersions = @('12.9.1.53980')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-CiscoJabber.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$installDirs = @("${env:ProgramFiles(x86)}\Cisco Systems\Cisco Jabber",
                 "$env:ProgramFiles\Cisco Systems\Cisco Jabber") | Select-Object -Unique

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

function Get-JabberEntries {
    param([switch]$AnyVersion)
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'Cisco Jabber*' -and ($AnyVersion -or (Test-TargetVersion $p.DisplayVersion))) {
                [pscustomobject]@{
                    KeyName          = $_.PSChildName
                    DisplayName      = $p.DisplayName
                    DisplayVersion   = $p.DisplayVersion
                    UninstallString  = $p.UninstallString
                    WindowsInstaller = $p.WindowsInstaller
                }
            }
        }
    }
}

function Get-JabberTargetExes {
    foreach ($dir in $installDirs) {
        $exe = Join-Path $dir 'CiscoJabber.exe'
        if ((Test-Path $exe) -and (Test-TargetVersion (Get-Item $exe).VersionInfo.ProductVersion)) { $exe }
    }
}

function Stop-Jabber {
    Get-Process -Name 'CiscoJabber', 'CiscoJabberPrt', 'CiscoJabberUpgrade', 'CiscoJabberCrashReporter' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start Cisco Jabber remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-JabberEntries)
    $exes    = @(Get-JabberTargetExes)

    if (-not $entries -and -not $exes) {
        Write-Log "Targeted Cisco Jabber not found. Nothing to do."
        Write-Output "Targeted Cisco Jabber not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    if (-not $removedNames) { $removedNames = $exes -join '; ' }
    Write-Log "Found: $removedNames"

    Stop-Jabber
    $rebootNeeded = $false

    foreach ($e in $entries) {
        $code = $null
        if ($e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $e.KeyName }
        elseif ($e.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') { $code = $Matches[1] }

        if (-not $code) {
            Write-Log "No MSI product code for $($e.DisplayName). UninstallString: $($e.UninstallString)"
            continue
        }

        $msiLog = Join-Path $logDir "CiscoJabber-MSI-Uninstall-$($code.Trim('{}')).log"
        Write-Log "Uninstalling MSI $code ($($e.DisplayName) $($e.DisplayVersion))"
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
             -ArgumentList "/x $code /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
        Write-Log "msiexec exit code: $($p.ExitCode)"

        switch ($p.ExitCode) {
            0     { }
            1605  { Write-Log "1605: product not installed (already removed)" }
            3010  { $rebootNeeded = $true }
            1641  { $rebootNeeded = $true }
            1603  { Write-Log "1603: fatal error - check $msiLog (search for 'Return value 3')" }
            1618  { Write-Log "1618: another installation in progress - will retry on next run" }
            default { }
        }
        Start-Sleep -Seconds 5
    }

    # ---- Clean leftovers only if NO Jabber version remains registered ----
    if (-not @(Get-JabberEntries -AnyVersion)) {
        Stop-Jabber
        foreach ($dir in $installDirs) {
            if (Test-Path $dir) {
                Write-Log "Removing leftover folder $dir"
                Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $dir) {
                    Write-Log "Some files in $dir are locked (likely Outlook add-in); they clear after reboot"
                    $rebootNeeded = $true
                }
            }
        }
        foreach ($lnk in @("$env:PUBLIC\Desktop\Cisco Jabber.lnk",
                           "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Cisco Jabber")) {
            if (Test-Path $lnk) {
                Write-Log "Removing $lnk"
                Remove-Item -Path $lnk -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # ---- Verify (registry entry + main exe) ----
    $remaining = @(Get-JabberEntries) + @(Get-JabberTargetExes)
    if ($remaining.Count -gt 0) {
        Write-Log "FAILED: Cisco Jabber still present"
        Write-Output "Failed: Cisco Jabber still present - see $logFile"
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