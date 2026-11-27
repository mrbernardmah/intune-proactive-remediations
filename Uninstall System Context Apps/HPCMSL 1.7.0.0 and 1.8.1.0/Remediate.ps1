<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls HP Client Management Script Library (CMSL, system context)
    at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - CMSL from the HP installer (hp-cmsl-x.y.z.exe) is an Inno Setup install. Its uninstaller
      is normally C:\Program Files\WindowsPowerShell\HP.CMSL.UninstallerData\unins000.exe and
      is run with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART.
    - MSI installs, if any, are handled with msiexec /x.
    - CMSL installed from the PowerShell Gallery (Install-Module HP.ClientManagement) has no
      Apps & Features entry and is NOT removed by this script.
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-HPCMSL.log
#>

# Versions to remove. Empty = ANY version. Must match the detection script.
$TargetVersions = @('1.7.0.0', '1.8.1.0')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-HPCMSL.log'

$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

function Write-Log([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

function ConvertTo-Version4([string]$v) {
    if (-not $v) { return $null }
    $parts = @($v.Trim() -split '[^\d]+' | Where-Object { $_ -ne '' } | Select-Object -First 4)
    while ($parts.Count -lt 4) { $parts += '0' }
    try { [version]($parts -join '.') } catch { $null }
}

function Test-TargetVersion([string]$Version) {
    $v = ConvertTo-Version4 $Version
    if (-not $v) { return $false }
    if ($TargetVersions.Count -eq 0) { return $true }
    foreach ($t in $TargetVersions) { if ($v -eq (ConvertTo-Version4 $t)) { return $true } }
    return $false
}

function Get-CMSLEntries {
    param([switch]$AnyVersion)
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'HP Client Management Script Library*' -and ($AnyVersion -or (Test-TargetVersion $p.DisplayVersion))) {
                [pscustomobject]@{
                    KeyPath              = $_.PSPath
                    KeyName              = $_.PSChildName
                    DisplayName          = $p.DisplayName
                    DisplayVersion       = $p.DisplayVersion
                    UninstallString      = $p.UninstallString
                    QuietUninstallString = $p.QuietUninstallString
                    InstallLocation      = $p.InstallLocation
                    WindowsInstaller     = $p.WindowsInstaller
                }
            }
        }
    }
}

try {
    Write-Log "===== Start HP CMSL remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-CMSLEntries)
    if (-not $entries) {
        Write-Log "Targeted HP CMSL not found. Nothing to do."
        Write-Output "Targeted HP CMSL not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    Write-Log "Found: $removedNames"
    $rebootNeeded = $false

    foreach ($e in $entries) {
        if ($e.WindowsInstaller -eq 1 -and $e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
            # ---- MSI ----
            $msiLog = Join-Path $logDir "HPCMSL-MSI-Uninstall-$($e.KeyName.Trim('{}')).log"
            Write-Log "Uninstalling MSI $($e.KeyName)"
            $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                 -ArgumentList "/x $($e.KeyName) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
            Write-Log "msiexec exit code: $($p.ExitCode)"
            if ($p.ExitCode -in 3010, 1641) { $rebootNeeded = $true }
            continue
        }

        # ---- Inno Setup (unins000.exe) ----
        $uninstaller = $null
        foreach ($s in @($e.QuietUninstallString, $e.UninstallString)) {
            if (-not $uninstaller -and $s) {
                if ($s -match '^\s*"([^"]+\.exe)"') { $uninstaller = $Matches[1] }
                elseif ($s -match '^\s*(\S+\.exe)') { $uninstaller = $Matches[1] }
            }
        }
        if (-not $uninstaller -or -not (Test-Path $uninstaller)) {
            $uninstaller = Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\HP.CMSL.UninstallerData" -Filter 'unins*.exe' -ErrorAction SilentlyContinue |
                           Select-Object -First 1 -ExpandProperty FullName
        }

        if (-not $uninstaller) {
            Write-Log "No uninstaller found for $($e.DisplayName) [$($e.DisplayVersion)]. UninstallString: $($e.UninstallString)"
            continue
        }

        $innoLog = Join-Path $logDir "HPCMSL-Uninstall-$($e.DisplayVersion).log"
        $uninstallArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$innoLog`"")
        Write-Log "Running: `"$uninstaller`" $($uninstallArgs -join ' ')"
        $p = Start-Process -FilePath $uninstaller -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
        Write-Log "Uninstaller exit code: $($p.ExitCode)"

        # Inno hands off to a temp copy of itself; wait for the uninstall entry to disappear
        for ($i = 0; $i -lt 60 -and (Test-Path $e.KeyPath); $i++) { Start-Sleep -Seconds 2 }
    }

    # ---- Verify ----
    if (@(Get-CMSLEntries).Count -gt 0) {
        Write-Log "FAILED: HP CMSL still present"
        Write-Output "Failed: HP CMSL still present - see $logFile"
        exit 1
    }

    # ---- Leftover uninstaller folder (only if no CMSL version remains registered) ----
    if (-not @(Get-CMSLEntries -AnyVersion)) {
        $uData = "$env:ProgramFiles\WindowsPowerShell\HP.CMSL.UninstallerData"
        if (Test-Path $uData) {
            Write-Log "Removing leftover folder $uData"
            Remove-Item -Path $uData -Recurse -Force -ErrorAction SilentlyContinue
        }
        $left = Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\Modules" -Directory -Filter 'HP.*' -ErrorAction SilentlyContinue
        if ($left) { Write-Log "Note: HP.* module folders still present (possibly PSGallery installs, left in place): $($left.Name -join ', ')" }
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