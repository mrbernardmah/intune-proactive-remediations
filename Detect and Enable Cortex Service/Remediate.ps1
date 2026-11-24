<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Starts the Cortex XDR agent service if Cortex XDR is installed and the
    service is not running. Does nothing on devices without Cortex XDR.

.NOTES
    Run as:            SYSTEM
    64-bit PowerShell: Yes
    Exit 0 = service running after remediation (or not applicable)
    Exit 1 = remediation failed

    Cortex XDR tamper protection can block changes to its services. If the
    start fails with "Access is denied", the agent's tamper-protection policy
    is blocking it and the device needs attention from the XDR console.
#>

$ServiceName    = 'cyserver'   # Cortex XDR main agent service
$CytoolPath     = Join-Path $env:ProgramFiles 'Palo Alto Networks\Traps\cytool.exe'
$TimeoutSeconds = 60

function Test-CortexXDRInstalled {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $app = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Cortex XDR*' -or $_.DisplayName -like 'Traps*' } |
        Select-Object -First 1
    if ($app) { return $true }
    if (Test-Path -LiteralPath $CytoolPath) { return $true }
    return $false
}

try {
    # Safety check: never act on devices without Cortex XDR
    if (-not (Test-CortexXDRInstalled)) {
        Write-Output "Cortex XDR not installed - no action taken."
        exit 0
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Output "Service '$ServiceName' not found - Cortex XDR agent needs reinstall. No action taken."
        exit 1
    }

    if ($svc.Status -eq 'Running') {
        Write-Output "Service '$ServiceName' already running."
        exit 0
    }

    # Make sure it isn't disabled (may be blocked by tamper protection - non-fatal)
    if ($svc.StartType -ne 'Automatic') {
        try {
            Set-Service -Name $ServiceName -StartupType Automatic -ErrorAction Stop
        }
        catch {
            Write-Output "Warning: could not set '$ServiceName' to Automatic: $($_.Exception.Message)"
        }
    }

    # Wait out any pending state before starting
    if ($svc.Status -in 'StartPending', 'StopPending') {
        try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30)) } catch { }
        $svc.Refresh()
    }

    if ($svc.Status -ne 'Running') {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }

    $svc.Refresh()
    try { $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSeconds)) } catch { }
    $svc.Refresh()

    if ($svc.Status -eq 'Running') {
        Write-Output "Service '$ServiceName' started successfully."
        exit 0
    }

    Write-Output "Service '$ServiceName' failed to reach Running within $TimeoutSeconds s (status: $($svc.Status))."
    exit 1
}
catch {
    Write-Output "Remediation error starting '$ServiceName': $($_.Exception.Message)"
    exit 1
}