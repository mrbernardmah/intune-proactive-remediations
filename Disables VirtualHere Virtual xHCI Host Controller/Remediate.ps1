<#
.SYNOPSIS
    Intune Remediation - REMEDIATION script.

.DESCRIPTION
    Disables the VirtualHere virtual xHCI host controller and restarts the Intel
    chipset USB controller (PCI\VEN_8086&DEV_4D7D) so the integrated camera
    reconnects. Fixes Code 31 / 0xC0000035 (STATUS_OBJECT_NAME_COLLISION) on
    HP ProBook 4 G2i.

    NOTE: VirtualHere USB sharing stops working on the device while its
    controller is disabled. The VirtualHere software is not uninstalled.
    To roll back: pnputil /enable-device "ROOT\USB\0000" (check instance ID).

.NOTES
    Intune settings: Run as SYSTEM = Yes (logged-on credentials = No),
                     Run in 64-bit PowerShell = Yes, Enforce signature check = No.
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\VirtualHereXhciConflict.log
#>

# --- Configuration -----------------------------------------------------------
$AffectedControllerIds = @('PCI\VEN_8086&DEV_4D7D*')
# -----------------------------------------------------------------------------

$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\VirtualHereXhciConflict.log'

function Write-Log {
    param([string]$Message)
    try {
        $line = '{0} [Remediate] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch { }
}

# Use the 64-bit pnputil even if the script host is 32-bit.
$PnpUtil = Join-Path $env:SystemRoot 'Sysnative\pnputil.exe'
if (-not (Test-Path $PnpUtil)) { $PnpUtil = Join-Path $env:SystemRoot 'System32\pnputil.exe' }

function Get-Device {
    param([string]$InstanceId)
    Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
}

try {
    $usbDevices = @(Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue)

    $virtualHere = @($usbDevices | Where-Object {
        $_.Manufacturer -like '*VirtualHere*' -or $_.FriendlyName -like 'VirtualHere*'
    })

    $intel = @($usbDevices | Where-Object {
        $id = $_.InstanceId
        @($AffectedControllerIds | Where-Object { $id -like $_ }).Count -gt 0
    })

    if ($intel.Count -eq 0) {
        Write-Log 'Affected Intel controller not present. Nothing to do.'
        Write-Output 'Not applicable: affected Intel USB controller not present'
        exit 0
    }

    # 1. Disable the VirtualHere controller(s)
    foreach ($vh in $virtualHere) {
        if ($vh.ConfigManagerErrorCode -eq 22) {
            Write-Log "Already disabled: $($vh.InstanceId)"
            continue
        }
        Write-Log "Disabling: $($vh.InstanceId) ($($vh.FriendlyName))"
        try {
            Disable-PnpDevice -InstanceId $vh.InstanceId -Confirm:$false -ErrorAction Stop
        }
        catch {
            Write-Log "Disable-PnpDevice failed ($($_.Exception.Message)); trying pnputil"
            $out = & $PnpUtil /disable-device "$($vh.InstanceId)" 2>&1
            Write-Log ($out -join ' ')
        }
    }

    Start-Sleep -Seconds 2

    # 2. Restart any failing Intel controller so it can claim its name
    foreach ($ctrl in $intel) {
        $current = Get-Device $ctrl.InstanceId
        if ($current.ConfigManagerErrorCode -eq 0) {
            Write-Log "Intel controller OK: $($ctrl.InstanceId)"
            continue
        }

        Write-Log "Restarting Intel controller (code $($current.ConfigManagerErrorCode)): $($ctrl.InstanceId)"
        $out = & $PnpUtil /restart-device "$($ctrl.InstanceId)" 2>&1
        Write-Log ($out -join ' ')
        Start-Sleep -Seconds 3

        $current = Get-Device $ctrl.InstanceId
        if ($current.ConfigManagerErrorCode -ne 0) {
            Write-Log 'Still failing after restart; trying disable/enable'
            try {
                Disable-PnpDevice -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 2
                Enable-PnpDevice  -InstanceId $ctrl.InstanceId -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 3
            }
            catch {
                Write-Log "Disable/enable failed: $($_.Exception.Message)"
            }
        }
    }

    # 3. Rescan so the camera and other child devices enumerate
    & $PnpUtil /scan-devices | Out-Null
    Start-Sleep -Seconds 3

    # 4. Verify
    $vhStillEnabled = @($virtualHere | ForEach-Object { Get-Device $_.InstanceId } |
        Where-Object { $_ -and $_.ConfigManagerErrorCode -ne 22 })
    $intelStillFailed = @($intel | ForEach-Object { Get-Device $_.InstanceId } |
        Where-Object { $_ -and $_.ConfigManagerErrorCode -ne 0 })

    if ($vhStillEnabled.Count -gt 0) {
        $msg = 'Failed: VirtualHere controller could not be disabled: ' + (($vhStillEnabled | ForEach-Object InstanceId) -join '; ')
        Write-Log $msg
        Write-Output $msg
        exit 1
    }

    if ($intelStillFailed.Count -gt 0) {
        $msg = 'VirtualHere disabled; Intel USB controller still failing - restart required: ' +
               (($intelStillFailed | ForEach-Object { '{0} (code {1})' -f $_.InstanceId, $_.ConfigManagerErrorCode }) -join '; ')
        Write-Log $msg
        Write-Output $msg
        exit 0
    }

    Write-Log 'Remediated: VirtualHere disabled and Intel USB controller working.'
    Write-Output 'Remediated: VirtualHere controller disabled; Intel USB controller started; camera should be available'
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}