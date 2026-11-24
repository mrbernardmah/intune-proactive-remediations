<#
.SYNOPSIS
    Intune Remediation - REMEDIATION script
    Applies power management settings (same registry values the Power.admx policies write),
    then applies them to the active power plan with powercfg so they take effect immediately.

      Allow Hibernate                                  = Allow (1)
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

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PolicyRoot             = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$LidActionGuid          = '5CA83367-6E45-459F-A27B-476B1D01C936'
$SleepAfterGuid         = '29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA'
$BalancedGuid           = '381b4222-f694-41f0-9685-ff5bb260df2e'
$OverlayKey             = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$OverlayBestPerformance = 'ded574b5-45a0-4f42-8737-46345c09c238'
$OverlayBalanced        = '00000000-0000-0000-0000-000000000000'

$LogDir  = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogPath = Join-Path -Path $LogDir -ChildPath 'Remediate-PowerSettings.log'

function Write-Log {
    param([string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogPath -Value $Line -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore logging failures so remediation isn't blocked
    }
    Write-Output $Line
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] $Value,
        [ValidateSet('DWord', 'String', 'QWord', 'ExpandString')]
        [string]$Type = 'DWord'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    Write-Log "Set $Path\$Name = $Value ($Type)"
}

function Invoke-PowerCfg {
    param([Parameter(Mandatory)] [string[]]$Arguments)

    $Proc = Start-Process -FilePath "$env:SystemRoot\System32\powercfg.exe" -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    $CmdDisplay = $Arguments -join ' '
    if ($Proc.ExitCode -eq 0) {
        Write-Log "powercfg $CmdDisplay (exit 0)"
    }
    else {
        Write-Log "WARNING: powercfg $CmdDisplay exited with code $($Proc.ExitCode)"
    }
}

try {
    Write-Log '--- Power settings remediation started ---'

    # 1. Allow Hibernate
    Invoke-PowerCfg -Arguments @('/hibernate', 'on')
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -Value 1 -Type 'DWord'

    # 2. Lid close action - Take no action (0)
    Set-RegValue -Path "$PolicyRoot\$LidActionGuid" -Name 'DCSettingIndex' -Value 0 -Type 'DWord'
    Set-RegValue -Path "$PolicyRoot\$LidActionGuid" -Name 'ACSettingIndex' -Value 0 -Type 'DWord'

    # 3. System sleep timeout - 0 seconds (never)
    Set-RegValue -Path "$PolicyRoot\$SleepAfterGuid" -Name 'DCSettingIndex' -Value 0 -Type 'DWord'
    Set-RegValue -Path "$PolicyRoot\$SleepAfterGuid" -Name 'ACSettingIndex' -Value 0 -Type 'DWord'

    # 4. Active power plan - Automatic (recommended) / Balanced
    Set-RegValue -Path $PolicyRoot -Name 'ActivePowerScheme' -Value $BalancedGuid -Type 'String'

    # 5. Apply settings to the active power scheme immediately
    $PowerCfgCommands = @(
        @('/setactive', $BalancedGuid),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0'),
        @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_BUTTONS', 'LIDACTION', '0'),
        @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'STANDBYIDLE', '0'),
        @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', 'STANDBYIDLE', '0'),
        @('/setactive', 'SCHEME_CURRENT')
    )
    foreach ($CmdArgs in $PowerCfgCommands) {
        Invoke-PowerCfg -Arguments $CmdArgs
    }

    # 6. Power Mode - Plugged in = Best Performance, On battery = Balanced
    Set-RegValue -Path $OverlayKey -Name 'ActiveOverlayAcPowerScheme' -Value $OverlayBestPerformance -Type 'String'
    Set-RegValue -Path $OverlayKey -Name 'ActiveOverlayDcPowerScheme' -Value $OverlayBalanced        -Type 'String'

    # Apply overlay for current power source via powrprof.dll
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
        $Batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
        if ($Batteries.Count -gt 0) {
            $Statuses = ($Batteries | ForEach-Object { $_.BatteryStatus }) -join ','
            # BatteryStatus 1 = Discharging
            if ($Batteries | Where-Object { $_.BatteryStatus -eq 1 }) {
                $OnAC = $false
            }
            Write-Log "Detected battery status(es): [$Statuses]; treating power source as $(if ($OnAC) {'AC'} else {'Battery'})"
        }
        else {
            Write-Log 'No Win32_Battery instance found; treating power source as AC'
        }

        $TargetOverlay = if ($OnAC) { $OverlayBestPerformance } else { $OverlayBalanced }
        $Result = [PowerOverlay]::PowerSetActiveOverlayScheme([Guid]$TargetOverlay)
        Write-Log "PowerSetActiveOverlayScheme($TargetOverlay) returned $Result"
    }
    catch {
        Write-Log "WARNING: could not apply power mode live ($($_.Exception.Message)). Registry values are set and will apply on next refresh/restart."
    }

    Write-Log '--- Power settings remediation completed ---'
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}