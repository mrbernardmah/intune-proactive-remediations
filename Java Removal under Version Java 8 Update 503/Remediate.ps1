# ==============================================================================
# Remediation Script: Remove Java (32-bit & 64-bit) older than 8.0.5030.01
# ==============================================================================

$TargetVersion = [version]"8.0.5030.01"

# Query both 64-bit and 32-bit registry uninstall keys
$RegistryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$OutdatedJava = Get-ItemProperty -Path $RegistryPaths -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.DisplayName -like "*Java*" -or $_.DisplayName -like "*SE Development Kit*") -and
        $_.DisplayVersion
    } |
    Where-Object {
        try {
            # Strip extra digits or trailing non-numeric components if present
            $cleanVersionString = ($_.DisplayVersion -split '-')[0]
            [version]$cleanVersion = $cleanVersionString
            $cleanVersion -lt $TargetVersion
        } catch {
            # If version parsing fails, fall back to explicit name check
            $_.DisplayName -like "*Java Auto Updater*"
        }
    }

if (-not $OutdatedJava) {
    Write-Output "No outdated Java installations found to remediate."
    exit 0
}

foreach ($app in $OutdatedJava) {
    $displayName    = $app.DisplayName
    $displayVersion = $app.DisplayVersion
    $productCode    = $app.PSChildName # Product Code GUID or key name
    $registryPath   = $app.PSPath      # Full registry path for cleanup if needed

    Write-Output "Attempting removal of: $displayName (Version: $displayVersion)"

    $uninstalledSuccessfully = $false

    # Strategy 1: MSI Product Code GUID
    if ($productCode -like "{*}") {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru
       
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Output "Successfully uninstalled $displayName."
            $uninstalledSuccessfully = $true
        } elseif ($process.ExitCode -eq 1605) {
            Write-Output "Warning: Exit code 1605 (Unknown/Orphaned Product). Cleaning up registry key."
            Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
            $uninstalledSuccessfully = $true
        } else {
            Write-Output "Failed to uninstall $displayName via MSI. Exit code: $($process.ExitCode)"
        }
    }

    # Strategy 2: Direct Execution of UninstallString (if Strategy 1 was skipped or didn't run)
    if (-not $uninstalledSuccessfully -and $app.UninstallString) {
        $uninstallCmd = $app.UninstallString

        # Handle MsiExec strings embedded in UninstallString
        if ($uninstallCmd -match "msiexec\.exe\s+(/I|/X)\s*(\{[^}]+\})" ) {
            $guid = $Matches[2]
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
           
            if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010 -or $process.ExitCode -eq 1605) {
                Write-Output "Successfully processed uninstall for $displayName."
                if ($process.ExitCode -eq 1605) {
                    Remove-Item -Path $registryPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Output "Failed executing UninstallString for $displayName. Exit code: $($process.ExitCode)"
            }
        } else {
            # Executable-based uninstallers (e.g., jucheck.exe or custom setup.exe)
            try {
                $exePath = ($uninstallCmd -split '"')[1]
                if (-not $exePath) { $exePath = ($uninstallCmd -split ' ')[0] }
                $argsList = $uninstallCmd.Replace($exePath, '').Trim() + " /s /qn /norestart"

                Start-Process -FilePath $exePath -ArgumentList $argsList -Wait -ErrorAction Stop
                Write-Output "Executed custom uninstall string for $displayName."
            } catch {
                Write-Output "Error executing uninstall for $displayName"
            }
        }
    }
}

exit 0