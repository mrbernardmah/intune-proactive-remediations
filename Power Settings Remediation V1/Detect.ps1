<#
.SYNOPSIS
    Intune Remediation - DETECTION script
    Checks power management settings.

    Exit 0 = Compliant (no remediation)
    Exit 1 = Non-compliant (remediation runs)

    Settings checked:
      Allow Hibernate                                  = Allow (1)
      Select Lid Close Action On Battery               = Take no action (0)
      Select Lid Close Action Plugged In               = Take no action (0)
      Specify the system sleep timeout (on battery)    = Enabled, 0 seconds
      Specify the system sleep timeout (plugged in)    = Enabled, 0 seconds
      Select an active power plan                      = Enabled, Automatic (recommended) / Balanced
      Power Mode (Settings app) - Plugged in           = Best Performance
      Power Mode (Settings app) - On battery           = Balanced

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

$Checks = @(
    @{ Name = 'Allow Hibernate';               Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'; Value = 'HibernateEnabled';           Expected = '1' }
    @{ Name = 'Lid close action (on battery)'; Path = "$PolicyRoot\$LidActionGuid";                  Value = 'DCSettingIndex';             Expected = '0' }
    @{ Name = 'Lid close action (plugged in)'; Path = "$PolicyRoot\$LidActionGuid";                  Value = 'ACSettingIndex';             Expected = '0' }
    @{ Name = 'Sleep timeout (on battery)';    Path = "$PolicyRoot\$SleepAfterGuid";                 Value = 'DCSettingIndex';             Expected = '0' }
    @{ Name = 'Sleep timeout (plugged in)';    Path = "$PolicyRoot\$SleepAfterGuid";                 Value = 'ACSettingIndex';             Expected = '0' }
    @{ Name = 'Active power plan';             Path = $PolicyRoot;                                   Value = 'ActivePowerScheme';          Expected = $BalancedGuid }
    @{ Name = 'Power mode (plugged in)';       Path = $OverlayKey;                                   Value = 'ActiveOverlayAcPowerScheme'; Expected = $OverlayBestPerformance }
    @{ Name = 'Power mode (on battery)';       Path = $OverlayKey;                                   Value = 'ActiveOverlayDcPowerScheme'; Expected = $OverlayBalanced }
)

try {
    $NonCompliant = [System.Collections.Generic.List[string]]::new()

    foreach ($Check in $Checks) {
        $CurrentRaw = $null
        if (Test-Path -LiteralPath $Check.Path) {
            $Item = Get-ItemProperty -LiteralPath $Check.Path -Name $Check.Value -ErrorAction SilentlyContinue
            if ($null -ne $Item) {
                $CurrentRaw = $Item.($Check.Value)
            }
        }

        $CurrentStr  = if ($null -eq $CurrentRaw) { '' } else { ([string]$CurrentRaw).Trim() }
        $ExpectedStr = ([string]$Check.Expected).Trim()

        if ($CurrentStr.ToLowerInvariant() -ne $ExpectedStr.ToLowerInvariant()) {
            $DisplayCurrent = if ([string]::IsNullOrEmpty($CurrentStr)) { 'not set' } else { $CurrentStr }
            $NonCompliant.Add("$($Check.Name) [current: $DisplayCurrent; expected: $ExpectedStr]")
        }
    }

    if ($NonCompliant.Count -gt 0) {
        Write-Output "Non-compliant: $($NonCompliant -join ' | ')"
        exit 1
    }

    Write-Output 'Compliant: all power settings are configured.'
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}