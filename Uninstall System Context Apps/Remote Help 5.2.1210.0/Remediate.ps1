<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Microsoft Remote Help (system context) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Remote Help is a setup bundle (remotehelpinstaller.exe). Uninstall uses the cached copy:
        <BundleCachePath> /uninstall /quiet acceptTerms=1 /norestart
      (command per Microsoft's Remote Help deployment docs; acceptTerms is case sensitive).
    - If the cached bundle is missing, any remaining Remote Help MSI is removed with
      msiexec /x {GUID} IGNOREDEPENDENCIES=ALL, then the orphaned bundle entry is cleared.
    - Closes RemoteHelp.exe first - this ends any Remote Help session in progress.
    - Microsoft Edge WebView2 Runtime is left installed (Remote Help never removes it).
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-RemoteHelp.log
#>

# Versions to remove. Empty = ANY version. Must match the detection script.
$TargetVersions = @('5.2.1210.0')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-RemoteHelp.log'

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

function Get-RemoteHelpEntries {
    param([switch]$AnyVersion)
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'Remote help*' -and ($AnyVersion -or (Test-TargetVersion $p.DisplayVersion))) {
                [pscustomobject]@{
                    KeyPath          = $_.PSPath
                    KeyName          = $_.PSChildName
                    DisplayName      = $p.DisplayName
                    DisplayVersion   = $p.DisplayVersion
                    BundleCachePath  = $p.BundleCachePath
                    UninstallString  = $p.UninstallString
                    WindowsInstaller = $p.WindowsInstaller
                    IsBundle         = [bool]$p.BundleCachePath
                }
            }
        }
    }
}

function Stop-RemoteHelp {
    Get-Process -Name 'RemoteHelp' -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "Stopping process $($_.Name) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Invoke-Msi([string]$Code, [string]$Label) {
    $msiLog = Join-Path $logDir "RemoteHelp-MSI-Uninstall-$($Code.Trim('{}')).log"
    $rc = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Log "msiexec /x $Code IGNOREDEPENDENCIES=ALL ($Label) - attempt $attempt"
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
             -ArgumentList "/x $Code IGNOREDEPENDENCIES=ALL /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
        $rc = $p.ExitCode
        Write-Log "msiexec exit code: $rc"
        if ($rc -ne 1618) { break }
        Start-Sleep -Seconds 30
    }
    return $rc
}

try {
    Write-Log "===== Start Remote Help remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-RemoteHelpEntries)
    if (-not $entries) {
        Write-Log "Targeted Remote Help not found. Nothing to do."
        Write-Output "Targeted Remote Help not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    Write-Log "Found: $removedNames"

    Stop-RemoteHelp
    $rebootNeeded = $false

    # ---- 1. Bundle uninstall (normal path) ----
    foreach ($b in ($entries | Where-Object { $_.IsBundle })) {
        if (Test-Path $b.BundleCachePath) {
            $bundleLog = Join-Path $logDir "RemoteHelp-Bundle-Uninstall.log"
            $uninstallArgs = @('/uninstall', '/quiet', 'acceptTerms=1', '/norestart', '/log', "`"$bundleLog`"")
            Write-Log "Running: `"$($b.BundleCachePath)`" $($uninstallArgs -join ' ')"
            $p = Start-Process -FilePath $b.BundleCachePath -ArgumentList $uninstallArgs -Wait -PassThru -WindowStyle Hidden
            Write-Log "Bundle exit code: $($p.ExitCode)  (0 = success, 3010/1641 = reboot needed)"
            if ($p.ExitCode -in 3010, 1641) { $rebootNeeded = $true }
            Start-Sleep -Seconds 5
        }
        else {
            Write-Log "Bundle cache missing: $($b.BundleCachePath) - falling back to MSI removal"
        }
    }

    # ---- 2. Fallback: remaining Remote Help MSIs ----
    foreach ($m in (@(Get-RemoteHelpEntries) | Where-Object { -not $_.IsBundle })) {
        $code = $null
        if ($m.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $m.KeyName }
        elseif ($m.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') { $code = $Matches[1] }
        if ($code) {
            $rc = Invoke-Msi $code $m.DisplayName
            if ($rc -in 3010, 1641) { $rebootNeeded = $true }
            if ($rc -eq 1605 -and (Test-Path $m.KeyPath)) {
                Write-Log "Removing orphaned Apps & Features entry $($m.KeyName)"
                Remove-Item -Path $m.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            Write-Log "Not an MSI, cannot remove silently: $($m.DisplayName) | $($m.UninstallString)"
        }
    }

    # ---- 3. Orphaned bundle entry (cache gone) ----
    foreach ($b in (@(Get-RemoteHelpEntries) | Where-Object { $_.IsBundle -and -not (Test-Path $_.BundleCachePath) })) {
        Write-Log "Removing orphaned bundle entry $($b.KeyName) ($($b.DisplayName))"
        Remove-Item -Path $b.KeyPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- 4. Leftovers (only if no Remote Help version remains) ----
    if (-not @(Get-RemoteHelpEntries -AnyVersion)) {
        $dir = "$env:ProgramFiles\Remote Help"
        if (Test-Path $dir) {
            Write-Log "Removing leftover folder $dir"
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
        $lnk = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Remote help.lnk"
        if (Test-Path $lnk) { Remove-Item -Path $lnk -Force -ErrorAction SilentlyContinue }
    }

    # ---- Verify ----
    if (@(Get-RemoteHelpEntries).Count -gt 0) {
        Write-Log "FAILED: Remote Help still present"
        Write-Output "Failed: Remote Help still present - see $logFile"
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