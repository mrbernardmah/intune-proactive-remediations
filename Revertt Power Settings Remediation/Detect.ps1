<#
.SYNOPSIS
    Intune Remediation - DETECTION script (pairs with Remediate-RevertPowerSettings.ps1)
    Checks that the power settings forced by the earlier "Remediate-PowerSettings"
    remediation have been removed.

    Exit 0 = Compliant (already reverted, nothing to do)
    Exit 1 = Non-compliant (remediation runs and reverts)

    Non-compliant if any of these are still present:
      - Lid close action policy      HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\5CA83367-...
      - System sleep timeout policy  HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\29F6C1DB-...
      - Active power plan policy     HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\ActivePowerScheme
      - Power mode not Balanced      ActiveOverlayAcPowerScheme / ActiveOverlayDcPowerScheme

    Plan values (sleep / lid timeouts in the power plan itself) are not checked, so a
    user's own later changes don't trigger the remediation again.

    Run as: SYSTEM | Run in 64-bit PowerShell: Yes
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$PolicyRoot     = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings'
$SchemesKey     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$OverlayDefault = '00000000-0000-0000-0000-000000000000'

$PolicyKeys = @(
    @{ Name = 'Lid close action policy';     Guid = '5ca83367-6e45-459f-a27b-476b1d01c936' }
    @{ Name = 'System sleep timeout policy'; Guid = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' }
)

try {
    $Found = [System.Collections.Generic.List[string]]::new()

    foreach ($P in $PolicyKeys) {
        if (Test-Path -LiteralPath (Join-Path $PolicyRoot $P.Guid)) {
            $Found.Add("$($P.Name) still set")
        }
    }

    if ((Test-Path -LiteralPath $PolicyRoot) -and
        $null -ne (Get-ItemProperty -LiteralPath $PolicyRoot -Name 'ActivePowerScheme' -ErrorAction SilentlyContinue)) {
        $Found.Add('Active power plan policy still set')
    }

    foreach ($Name in 'ActiveOverlayAcPowerScheme', 'ActiveOverlayDcPowerScheme') {
        $Value = (Get-ItemProperty -LiteralPath $SchemesKey -Name $Name -ErrorAction SilentlyContinue).$Name
        if ($null -ne $Value -and ([string]$Value).Trim().ToLowerInvariant() -ne $OverlayDefault) {
            $Found.Add("$Name is $Value (expected Balanced)")
        }
    }

    if ($Found.Count -gt 0) {
        Write-Output "Non-compliant: $($Found -join ' | ')"
        exit 1
    }

    Write-Output 'Compliant: power settings are at Windows defaults.'
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}