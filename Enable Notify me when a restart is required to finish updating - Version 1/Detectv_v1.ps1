# Stop any previous logging
try { Stop-Transcript } catch {}

# Log
$logFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\Detect-RebootNotification.log"
Start-Transcript -Append -Path $logFile

# Default Exit Code (1 = fail)
$exitCode = 1

try {
    # Reg Key Used
    $registryPath = "HKLM:\Software\Microsoft\WindowsUpdate\UX\Settings"
    $registryKey  = "RestartNotificationsAllowed2"
    
    # Get key
    $regProps = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
    
    if (-not $regProps) {
        Write-Output "Key doesn't exist"
    }
    elseif (-not ($regProps.PSObject.Properties.Name -contains $registryKey)) {
        Write-Output "Property doesn't exist"
    }
    else {
        $value = $regProps.$registryKey
        
        if ($value -eq 1) {
            Write-Output "Key '$registryPath\$registryKey' equals 1."
            $exitCode = 0
        }
        else {
            Write-Output "Key '$registryPath\$registryKey' Does not equals 1. Value is $value."
        }
    }
}
catch {
    Write-Error "Error : $_"
}
finally {
    Stop-Transcript
    exit $exitCode
}