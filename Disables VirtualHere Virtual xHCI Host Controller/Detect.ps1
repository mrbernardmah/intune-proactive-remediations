<#
.SYNOPSIS
    Intune Remediation - DETECTION script.

.DESCRIPTION
    Detects the VirtualHere virtual xHCI host controller conflicting with the
    Intel chipset USB controller (PCI\VEN_8086&DEV_4D7D) on HP ProBook 4 G2i.
    The conflict causes Code 31 / 0xC0000035 (STATUS_OBJECT_NAME_COLLISION) on the
    Intel controller, which disconnects the integrated camera.

    Exit 0 = compliant or not applicable (no remediation)
    Exit 1 = VirtualHere controller enabled on affected hardware, or the Intel
             controller is still failing (remediation required)

.NOTES
    Intune settings: Run as SYSTEM = Yes (logged-on credentials = No),
                     Run in 64-bit PowerShell = Yes, Enforce signature check = No.
    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\VirtualHereXhciConflict.log
#>

# --- Configuration -----------------------------------------------------------
# Intel controller(s) affected by the conflict (wildcards allowed).
$AffectedControllerIds = @('PCI\VEN_8086&DEV_4D7D*')

# $true  = only flag the device when the Intel controller is actually failing.
# $false = flag whenever VirtualHere is enabled on affected hardware (proactive).
$OnlyWhenControllerFailing = $false
# -----------------------------------------------------------------------------

$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\VirtualHereXhciConflict.log'

function Write-Log {
    param([string]$Message)
    try {
        $line = '{0} [Detect] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    } catch { }
}

try {
    $usbDevices = @(Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue)

    $virtualHere = @($usbDevices | Where-Object {
        $_.Manufacturer -like '*VirtualHere*' -or $_.FriendlyName -like 'VirtualHere*'
    })

    if ($virtualHere.Count -eq 0) {
        Write-Log 'VirtualHere controller not present. Compliant.'
        Write-Output 'Compliant: VirtualHere controller not present'
        exit 0
    }

    $intel = @($usbDevices | Where-Object {
        $id = $_.InstanceId
        @($AffectedControllerIds | Where-Object { $id -like $_ }).Count -gt 0
    })

    if ($intel.Count -eq 0) {
        Write-Log 'Affected Intel controller not present. Not applicable.'
        Write-Output 'Not applicable: affected Intel USB controller not present'
        exit 0
    }

    # ConfigManagerErrorCode: 0 = working, 22 = disabled, 31 = failed to load
    $vhEnabled   = @($virtualHere | Where-Object { $_.ConfigManagerErrorCode -ne 22 })
    $intelFailed = @($intel | Where-Object { $_.ConfigManagerErrorCode -ne 0 })

    $vhSummary    = ($virtualHere | ForEach-Object { '{0} (code {1})' -f $_.InstanceId, $_.ConfigManagerErrorCode }) -join '; '
    $intelSummary = ($intel | ForEach-Object { '{0} (code {1})' -f $_.InstanceId, $_.ConfigManagerErrorCode }) -join '; '
    Write-Log "VirtualHere: $vhSummary"
    Write-Log "Intel: $intelSummary"

    if ($intelFailed.Count -gt 0) {
        Write-Output "Non-compliant: Intel USB controller failing ($intelSummary); VirtualHere enabled=$($vhEnabled.Count)"
        exit 1
    }

    if ($vhEnabled.Count -gt 0 -and -not $OnlyWhenControllerFailing) {
        Write-Output "Non-compliant: VirtualHere controller enabled on affected hardware ($vhSummary)"
        exit 1
    }

    Write-Log 'Compliant.'
    Write-Output 'Compliant: VirtualHere controller disabled and Intel USB controller working'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}