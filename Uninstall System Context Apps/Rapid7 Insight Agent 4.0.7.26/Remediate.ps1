<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Silently uninstalls Rapid7 Insight Agent (system context, MSI) at the targeted version(s).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    - Uninstalls via msiexec /x {ProductCode} /qn /norestart (verbose MSI log kept).
    - The MSI stops and removes the ir_agent service itself; the script does not
      force-kill the agent.
    - Only removes the leftover "Rapid7\Insight Agent" folder AFTER a successful
      uninstall (no registry entry left).
    - Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-Rapid7InsightAgent.log
#>

# Versions to remove. Empty = ANY version. Must match the detection script.
$TargetVersions = @('4.0.7.26')

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-Rapid7InsightAgent.log'

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

function Get-InsightAgentEntries {
    param([switch]$AnyVersion)
    foreach ($root in $uninstallRoots) {
        Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like 'Rapid7 Insight Agent*' -and ($AnyVersion -or (Test-TargetVersion $p.DisplayVersion))) {
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

try {
    Write-Log "===== Start Rapid7 Insight Agent remediation (target: $($TargetVersions -join ', ')) ====="

    $entries = @(Get-InsightAgentEntries)
    if (-not $entries) {
        Write-Log "Targeted Insight Agent not found. Nothing to do."
        Write-Output "Targeted Rapid7 Insight Agent not found"
        exit 0
    }

    $removedNames = ($entries | ForEach-Object { "$($_.DisplayName) [$($_.DisplayVersion)]" }) -join '; '
    Write-Log "Found: $removedNames"

    $rebootNeeded = $false
    $failures = @()

    foreach ($e in $entries) {
        # Product code: the key name, or parsed from UninstallString (MsiExec.exe /X{GUID})
        $code = $null
        if ($e.KeyName -match '^\{[0-9A-Fa-f\-]{36}\}$') { $code = $e.KeyName }
        elseif ($e.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') { $code = $Matches[1] }

        if (-not $code) {
            Write-Log "No MSI product code found for $($e.DisplayName). UninstallString: $($e.UninstallString)"
            $failures += $e.DisplayName
            continue
        }

        $msiLog = Join-Path $logDir "Rapid7-MSI-Uninstall-$($code.Trim('{}')).log"
        Write-Log "Uninstalling MSI $code ($($e.DisplayName) $($e.DisplayVersion))"
        $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
             -ArgumentList "/x $code /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -WindowStyle Hidden
        Write-Log "msiexec exit code: $($p.ExitCode)"

        switch ($p.ExitCode) {
            0     { }
            1605  { Write-Log "1605: product not installed (already removed)" }
            3010  { $rebootNeeded = $true }
            1641  { $rebootNeeded = $true }
            1603  { Write-Log "1603: fatal error - check $msiLog (search for 'Return value 3'). Uninstall protection on the agent is a common cause."; $failures += $code }
            1618  { Write-Log "1618: another installation is in progress - will retry on next remediation run"; $failures += $code }
            default { $failures += $code }
        }
        Start-Sleep -Seconds 5
    }

    # ---- Verify ----
    if (@(Get-InsightAgentEntries).Count -gt 0) {
        Write-Log "FAILED: Insight Agent still present"
        Write-Output "Failed: Rapid7 Insight Agent still present - see $logFile"
        exit 1
    }

    # ---- Clean leftovers only if NO Insight Agent version remains ----
    if (-not @(Get-InsightAgentEntries -AnyVersion)) {
        $svc = Get-Service -Name 'ir_agent' -ErrorAction SilentlyContinue
        if ($svc) { Write-Log "Note: ir_agent service still registered (state: $($svc.Status)) - leaving it for reboot/MSI cleanup" }
        else {
            $leftover = "$env:ProgramFiles\Rapid7\Insight Agent"
            if (Test-Path $leftover) {
                Write-Log "Removing leftover folder $leftover"
                Remove-Item -Path $leftover -Recurse -Force -ErrorAction SilentlyContinue
                $parent = "$env:ProgramFiles\Rapid7"
                if ((Test-Path $parent) -and -not (Get-ChildItem -Path $parent -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -Path $parent -Force -ErrorAction SilentlyContinue
                }
            }
        }
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