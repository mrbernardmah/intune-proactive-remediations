<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Checks that the Cortex XDR agent service is running, but only on devices
    where Cortex XDR is actually installed.

.NOTES
    Run as:            SYSTEM
    64-bit PowerShell: Yes
    Exit 0 = compliant (or Cortex XDR not installed -> nothing to do)
    Exit 1 = Cortex XDR installed but service not running -> run remediation
#>

$ServiceName = 'cyserver'   # Cortex XDR main agent service
$CytoolPath  = Join-Path $env:ProgramFiles 'Palo Alto Networks\Traps\cytool.exe'

function Test-CortexXDRInstalled {
    # 1. Uninstall registry entry (64-bit and 32-bit hives)
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $app = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Cortex XDR*' -or $_.DisplayName -like 'Traps*' } |
        Select-Object -First 1
    if ($app) { return $true }

    # 2. Agent binary on disk
    if (Test-Path -LiteralPath $CytoolPath) { return $true }

    return $false
}

try {
    if (-not (Test-CortexXDRInstalled)) {
        Write-Output "Cortex XDR not installed - not applicable."
        exit 0
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        # Installed but service missing = broken install; remediation can't fix this by starting a service
        Write-Output "Cortex XDR installed but service '$ServiceName' not found - agent may need reinstall."
        exit 1
    }

    if ($svc.Status -eq 'Running') {
        Write-Output "Cortex XDR service '$ServiceName' is running."
        exit 0
    }

    Write-Output "Cortex XDR service '$ServiceName' is $($svc.Status) (StartType: $($svc.StartType))."
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}