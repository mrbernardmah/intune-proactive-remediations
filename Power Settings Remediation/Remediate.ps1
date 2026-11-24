<#
.SYNOPSIS
    Intune Remediation - REMEDIATION script
    Applies power management settings (same registry values the Power.admx policies write),
    then applies them to the active power plan with powercfg so they take effect straight away.

      Allow Hibernate                                  = Allow
      Select Lid Close Action On Battery               = Take no action (0)
      Select Lid Close Action Plugged In               = Take no action (0)
      Specify the system sleep timeout (on battery)    = Enabled, 0 seconds
      Specify the system sleep timeout (plugged in)    = Enabled, 0 seconds
      Select an active power plan                      = Enabled, Automatic (recommended) / Balanced
      Power Mode (Settings app) - Plugged in           = Best Performance
      Power Mode (Settings app) - On battery           = Balanced

    Note: Power Mode is set per power source on Windows 11 24H2 and later. It is not a
    policy, so users can still change it afterwards in Settings.

    Run as: SYSTEM | Run in 64-bit PowerShell: Yes
#>

$ErrorActionPreference = 'Stop'

$PolicyRoot      = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$LidActionGuid   = '5CA83367-6E45-459F-A27B-476B1D01C936'   # Lid switch close action
$SleepAfterGuid  = '29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA'   # Sleep after (standby timeout)
$BalancedGuid    = '381b4222-f694-41f0-9685-ff5bb260df2e'   # Automatic (recommended) = Balanced

# Power Mode overlays (Settings > System > Power & battery > Power mode)
$OverlayKey             = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$OverlayBestPerformance = 'ded574b5-45a0-4f42-8737-46345c09c238'
$OverlayBalanced        = '00000000-0000-0000-0000-000000000000'

$LogPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\Remediate-PowerSettings.log"
function Write-Log { param([string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -Path $LogPath -Value $Line -ErrorAction SilentlyContinue
    Write-Output $Line
}

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Log "Set $Path\$Name = $Value ($Type)"
}

try {
    Write-Log '--- Power settings remediation started ---'

    # 1. Allow Hibernate
    #    (Power/AllowHibernate has no effect if hibernate was turned off with powercfg,
    #     so turn it on directly as well.)
    & powercfg.exe /hibernate on 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log 'WARNING: powercfg /hibernate on failed (hardware/firmware may not support hibernate). Setting registry value anyway.' }
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -Value 1

    # 2. Lid close action - Take no action (0)
    Set-RegValue -Path "$PolicyRoot\$LidActionGuid" -Name 'DCSettingIndex' -Value 0   # On battery
    Set-RegValue -Path "$PolicyRoot\$LidActionGuid" -Name 'ACSettingIndex' -Value 0   # Plugged in

    # 3. System sleep timeout - 0 seconds (never)
    Set-RegValue -Path "$PolicyRoot\$SleepAfterGuid" -Name 'DCSettingIndex' -Value 0  # On battery
    Set-RegValue -Path "$PolicyRoot\$SleepAfterGuid" -Name 'ACSettingIndex' -Value 0  # Plugged in

    # 4. Active power plan - Automatic (recommended) / Balanced
    Set-RegValue -Path $PolicyRoot -Name 'ActivePowerScheme' -Value $BalancedGuid -Type 'String'

    # 5. Apply to the plan now so no reboot or policy refresh is needed
    $Commands = @(
        "/setactive $BalancedGuid",
        '/setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0',
        '/setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0',
        '/setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0',
        '/setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0',
        '/setactive SCHEME_CURRENT'
    )
    foreach ($Cmd in $Commands) {
        $Out = Start-Process -FilePath 'powercfg.exe' -ArgumentList $Cmd -Wait -NoNewWindow -PassThru
        Write-Log "powercfg $Cmd (exit $($Out.ExitCode))"
    }

    # 6. Power Mode - Plugged in = Best Performance, On battery = Balanced
    #    Power Mode only applies on top of the Balanced plan (set above).
    Set-RegValue -Path $OverlayKey -Name 'ActiveOverlayAcPowerScheme' -Value $OverlayBestPerformance -Type 'String'
    Set-RegValue -Path $OverlayKey -Name 'ActiveOverlayDcPowerScheme' -Value $OverlayBalanced        -Type 'String'

    # Apply the mode for the current power source now through the power API
    # (powrprof.dll PowerSetActiveOverlayScheme - the call the Settings app uses).
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
        $OnAC = $true
        $Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        if ($Battery -and ($Battery | Where-Object { $_.BatteryStatus -eq 1 })) { $OnAC = $false }  # 1 = discharging

        $CurrentOverlay = if ($OnAC) { $OverlayBestPerformance } else { $OverlayBalanced }
        $Result = [PowerOverlay]::PowerSetActiveOverlayScheme([Guid]$CurrentOverlay)
        Write-Log "PowerSetActiveOverlayScheme($CurrentOverlay) on $(if ($OnAC) {'AC'} else {'battery'}) returned $Result"
    }
    catch {
        Write-Log "WARNING: could not apply power mode live ($($_.Exception.Message)). Registry values are set and apply after restart."
    }

    Write-Log '--- Power settings remediation completed ---'
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}