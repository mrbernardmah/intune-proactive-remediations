# Stop any previous logging
try { Stop-Transcript } catch {}

# Log file path
$logFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\Remediate-RebootNotification.log"
Start-Transcript -Append -Path $logFile

# Default exit code (0 = success, 1 = failure)
$exitCode = 1

try {
    # Registry path and key
    $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"
    $registryKey  = "RestartNotificationsAllowed2"

    # Ensure registry path exists
    if (-not (Test-Path $registryPath)) {
        Write-Output "Registry path does not exist. Creating..."
        New-Item -Path $registryPath -Force | Out-Null
    }

    # Set the registry key to 1
    Write-Output "Setting '$registryPath\$registryKey' to 1..."
    Set-ItemProperty -Path $registryPath -Name $registryKey -Value 1 -Force | Out-Null

    # Confirm the change
    $value = (Get-ItemProperty -Path $registryPath -Name $registryKey).$registryKey
    if ($value -eq 1) {
        Write-Output "Successfully set '$registryPath\$registryKey' to 1."
        $exitCode = 0
    } else {
        Write-Output "Failed to set '$registryPath\$registryKey'. Current value: $value"
    }
}
catch {
    Write-Error "Error: $_"
}
finally {
    try { Stop-Transcript } catch {}
    exit $exitCode
}
