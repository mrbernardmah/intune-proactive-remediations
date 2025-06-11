try { Stop-Transcript } catch {}

# Log files
$logFile = "$($env:ProgramData)\Microsoft\IntuneManagementExtension\Logs\Remediate-RebootNotification.log"
Start-Transcript -Append -Path $LogFile

try {
    # Reg keys
    $RegistryPath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    $RegistryKey = "RestartNotificationsAllowed2"

    # Is it already remediated

    $Value = Get-ItemProperty -Path $RegistryPath -Name $RegistryKey | Select-Object -ExpandProperty $RegistryKey
    if ($Value -ne 1) {
        Write-Output "Key $RegistryPath\$RegistryKey is not equals to 1. Remediating..."
        Set-ItemProperty -Path $RegistryPath -Name $RegistryKey -Value 1 | Out-Null
        Write-Output "Key $RegistryPath\$RegistryKey has been updated to 1."
    } else {
        Write-Output "Key $RegistryPath\$RegistryKey is already equals to 1. No action needed."
    }
    Stop-Transcript
    exit 0
} catch {
    Write-Error "Error : $_"
    Stop-Transcript
    exit 1
}