<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Wireshark (system context) at the targeted version(s).
    Handles both NSIS (.exe) and MSI installs.

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Closes running Wireshark / TShark / dumpcap processes started from the install folder.
    - Npcap is a separate product and is KEPT by default (other tools such as Nmap use it).
      Set $RemoveNpcap = $true to remove it as well.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-Wireshark.log
#>

# Versions to remove. Empty = ANY Wireshark version. Must match the detection script.
$TargetVersions = @('4.6.6')
$RemoveNpcap    = $false

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-Wireshark.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

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

function Get-WiresharkEntries {
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'Wireshark*' -and (Test-TargetVersion $p.DisplayVersion)) {
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

function Get-WiresharkFolders {
    @("$env:ProgramFiles\Wireshark", "${env:ProgramFiles(x86)}\Wireshark") |
        Select-Object -Unique |
        Where-Object {
            $exe = Join-Path $_ 'Wireshark.exe'
            (Test-Path $exe) -and (Test-TargetVersion (Get-Item $exe).VersionInfo.ProductVersion)
        }
}

function Stop-Wireshark {
    $names = 'Wireshark', 'tshark', 'dumpcap', 'rawshark', 'capinfos', 'editcap', 'mergecap', 'text2pcap', 'extcap', 'sharkd', 'Stratoshark'
    Get-Process -Name $names -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -like '*\Wireshark\*' } |
        ForEach-Object {
            Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    Start-Sleep -Seconds 2
}

try {
    Write-Log "===== Start Wireshark remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-WiresharkEntries)
    $folders = @(Get-WiresharkFolders)

    if (-not $entries -and -not $folders) {
        Write-Log "Targeted Wireshark not found. Nothing to do."
        Write-Output "Targeted Wireshark not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    Write-Log "Found: $removedNames $($folders -join '; ')"

    Stop-Wireshark

    foreach ($e in $entries) {
        if ($e.WindowsInstaller -eq 1 -and $e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
            # ---- MSI install ----
            $msiLog = Join-Path $logDir "Wireshark-MSI-Uninstall-$($e.KeyName.Trim('{}')).log"
            Write-Log "Uninstalling MSI $($e.KeyName) ($($e.DisplayName))"
            $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                 -ArgumentList "/x $($e.KeyName) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
            Write-Log "msiexec exit code: $($p.ExitCode)  (0/3010 = success, 1605 = not installed)"
        }
        else {
            # ---- NSIS install (uninstall-wireshark.exe / uninstall.exe) ----
            $uninstaller = $null
            if ($e.UninstallString -match '^\s*"([^"]+\.exe)"') { $uninstaller = $Matches[1] }
            elseif ($e.UninstallString -match '^\s*(\S+\.exe)') { $uninstaller = $Matches[1] }

            if (-not $uninstaller -or -not (Test-Path $uninstaller)) {
                $dir = if ($e.InstallLocation) { $e.InstallLocation.TrimEnd('\') } else { "$env:ProgramFiles\Wireshark" }
                $uninstaller = @("$dir\uninstall-wireshark.exe", "$dir\uninstall.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            }

            if ($uninstaller) {
                $installDir = Split-Path $uninstaller -Parent
                # _?= makes the NSIS uninstaller run in place and wait, instead of
                # copying itself to %TEMP% and returning immediately.
                Write-Log "Running: `"$uninstaller`" /S _?=$installDir"
                $p = Start-Process -FilePath $uninstaller -ArgumentList "/S", "_?=$installDir" -Wait -PassThru -WindowStyle Hidden
                Write-Log "Uninstaller exit code: $($p.ExitCode)"
                # With _?= the uninstaller can't delete itself; remove it now
                Remove-Item -Path $uninstaller -Force -ErrorAction SilentlyContinue
            }
            else {
                Write-Log "No uninstaller found for $($e.DisplayName); will clean up manually"
            }
        }
        Start-Sleep -Seconds 3
    }

    # ---- Optional: Npcap ----
    if ($RemoveNpcap) {
        $npcapUninst = "$env:ProgramFiles\Npcap\Uninstall.exe"
        if (Test-Path $npcapUninst) {
            Write-Log "Uninstalling Npcap"
            $p = Start-Process -FilePath $npcapUninst -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
            Write-Log "Npcap uninstaller exit code: $($p.ExitCode)"
        }
    }

    # ---- Clean up leftovers ----
    Stop-Wireshark
    foreach ($dir in @("$env:ProgramFiles\Wireshark", "${env:ProgramFiles(x86)}\Wireshark")) {
        $exe = Join-Path $dir 'Wireshark.exe'
        $isTarget = (Test-Path $exe) -and (Test-TargetVersion (Get-Item $exe).VersionInfo.ProductVersion)
        $isEmptyShell = (Test-Path $dir) -and -not (Test-Path $exe)
        if ($isTarget -or $isEmptyShell) {
            Write-Log "Removing leftover folder $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($e in @(Get-WiresharkEntries)) {
        if ($e.WindowsInstaller -ne 1) {
            Write-Log "Removing orphaned uninstall key $($e.KeyName)"
            Remove-Item -Path $e.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($lnk in @("$env:PUBLIC\Desktop\Wireshark.lnk",
                       "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Wireshark.lnk")) {
        if (Test-Path $lnk) {
            Write-Log "Removing shortcut $lnk"
            Remove-Item -Path $lnk -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- Verify ----
    $remaining = @(Get-WiresharkEntries) + @(Get-WiresharkFolders)
    if ($remaining.Count -gt 0) {
        Write-Log "FAILED: Wireshark still present"
        Write-Output "Failed: targeted Wireshark still present"
        exit 1
    }

    Write-Log "SUCCESS: Wireshark removed"
    Write-Output "Success: removed $removedNames"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}