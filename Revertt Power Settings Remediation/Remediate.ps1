<#
.SYNOPSIS
    Intune Remediation - REMEDIATION script (pairs with Detect-RevertPowerSettings.ps1)
    Reverts the changes made by the "Remediate-PowerSettings" Intune remediation back to
    Windows defaults.

      Lid close action (on battery / plugged in)  -> removes the policy and restores the
                                                     Windows/OEM default for the plan (normally Sleep)
      System sleep timeout (on battery / plugged in) -> removes the policy and restores the
                                                     Windows/OEM default for the plan
      Select an active power plan                 -> removes the policy (Balanced stays active,
                                                     which is the Windows default)
      Power Mode (plugged in / on battery)        -> Balanced (Windows default)
      Allow Hibernate                             -> left as is (1 = Windows default on most devices)

    Removes only the policy values the remediation wrote. Other policies under
    HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings (for example the CIS
    "require a password on wake" setting) are left alone.

    Unassign the original remediation first, or it will put the settings back.

    Run as: SYSTEM | Run in 64-bit PowerShell: Yes
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PolicyRoot      = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$DefaultsRoot    = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings'
$SchemesKey      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$OverlayDefault  = '00000000-0000-0000-0000-000000000000'

# Plan settings the remediation changed: sub-group GUID, setting GUID, built-in fallback defaults
$PlanSettings = @(
    @{ Name = 'Lid close action'; Sub = '4f971e89-eebd-4455-a8de-9e59040e7347'; Set = '5ca83367-6e45-459f-a27b-476b1d01c936'; FallbackAC = 1;    FallbackDC = 1   }  # 1 = Sleep
    @{ Name = 'Sleep timeout';    Sub = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; Set = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'; FallbackAC = 1800; FallbackDC = 900 }  # seconds
)

$LogDir  = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogPath = Join-Path -Path $LogDir -ChildPath 'Remediate-RevertPowerSettings.log'

function Write-Log {
    param([string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $LogPath -Value $Line -ErrorAction SilentlyContinue
    } catch { }
    Write-Output $Line
}

function Invoke-PowerCfg {
    param([Parameter(Mandatory)] [string[]]$Arguments)
    $Proc = Start-Process -FilePath "$env:SystemRoot\System32\powercfg.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    $Cmd  = $Arguments -join ' '
    if ($Proc.ExitCode -eq 0) { Write-Log "powercfg $Cmd (exit 0)" }
    else { Write-Log "WARNING: powercfg $Cmd exited with code $($Proc.ExitCode)" }
}

try {
    Write-Log '--- Power settings revert started ---'

    # 1. Remove the policy values the remediation wrote (these cause the admin banner)
    foreach ($S in $PlanSettings) {
        $Key = Join-Path $PolicyRoot $S.Set
        if (Test-Path -LiteralPath $Key) {
            Remove-Item -LiteralPath $Key -Recurse -Force
            Write-Log "Removed policy key $Key"
        }
    }
    if ((Test-Path -LiteralPath $PolicyRoot) -and
        $null -ne (Get-ItemProperty -LiteralPath $PolicyRoot -Name 'ActivePowerScheme' -ErrorAction SilentlyContinue)) {
        Remove-ItemProperty -LiteralPath $PolicyRoot -Name 'ActivePowerScheme' -Force
        Write-Log "Removed $PolicyRoot\ActivePowerScheme"
    }
    # Tidy up the PowerSettings policy key only if nothing else is left in it
    if ((Test-Path -LiteralPath $PolicyRoot) -and
        -not (Get-ChildItem -LiteralPath $PolicyRoot) -and
        -not ((Get-Item -LiteralPath $PolicyRoot).Property)) {
        Remove-Item -LiteralPath $PolicyRoot -Force
        Write-Log "Removed empty key $PolicyRoot"
    }

    # 2. Restore the plan's default values (Windows/OEM defaults for the active plan)
    $Scheme = (Get-ItemProperty -LiteralPath $SchemesKey -Name 'ActivePowerScheme').ActivePowerScheme
    Write-Log "Active power scheme: $Scheme"

    foreach ($S in $PlanSettings) {
        $DefKey = Join-Path $DefaultsRoot "$($S.Sub)\$($S.Set)\DefaultPowerSchemeValues\$Scheme"
        $Def    = Get-ItemProperty -LiteralPath $DefKey -ErrorAction SilentlyContinue
        $AC     = if ($null -ne $Def.ACSettingIndex) { $Def.ACSettingIndex } else { $S.FallbackAC }
        $DC     = if ($null -ne $Def.DCSettingIndex) { $Def.DCSettingIndex } else { $S.FallbackDC }
        $Source = if ($Def) { 'plan default' } else { 'built-in fallback' }
        Write-Log "$($S.Name): restoring AC=$AC DC=$DC ($Source)"

        Invoke-PowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', $S.Sub, $S.Set, "$AC")
        Invoke-PowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', $S.Sub, $S.Set, "$DC")
    }
    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT')

    # 3. Power Mode back to Balanced for both power sources
    New-ItemProperty -Path $SchemesKey -Name 'ActiveOverlayAcPowerScheme' -Value $OverlayDefault -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $SchemesKey -Name 'ActiveOverlayDcPowerScheme' -Value $OverlayDefault -PropertyType String -Force | Out-Null
    Write-Log "Set power mode (AC and DC) to Balanced ($OverlayDefault)"

    try {
        if (-not ('PowerOverlay' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PowerOverlay {
    [DllImport("powrprof.dll", EntryPoint = "PowerSetActiveOverlayScheme")]
    public static extern uint PowerSetActiveOverlayScheme(Guid OverlaySchemeGuid);
}
'@
        }
        $Result = [PowerOverlay]::PowerSetActiveOverlayScheme([Guid]$OverlayDefault)
        Write-Log "PowerSetActiveOverlayScheme($OverlayDefault) returned $Result"
    }
    catch {
        Write-Log "WARNING: could not apply power mode live ($($_.Exception.Message)). Registry values are set and will apply after restart."
    }

    Write-Log '--- Power settings revert completed ---'
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}