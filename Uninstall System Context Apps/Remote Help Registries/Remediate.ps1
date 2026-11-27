<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Removes the uninstall registry key
    HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{421B3A26-5838-4EBA-AA36-C5A12A069D9E}

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : No  (runs as SYSTEM)
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes   (required - the path names WOW6432Node explicitly)

    - Exports a .reg backup of the key before deleting it.
    - Logs whether Windows Installer still has this product registered. If it does, the app
      may still be installed and deleting this key only hides it from Apps & Features.
    - Log + backup: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
#>

$ProductCode = '{421B3A26-5838-4EBA-AA36-C5A12A069D9E}'
$KeyPath     = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode"
$RegExePath  = "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$ProductCode"

$ErrorActionPreference = 'Stop'

$logDir = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir 'Remediate-OrphanUninstallKey.log'

function Write-Log([string]$Message) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
}

# Windows Installer stores product codes "packed" (each GUID group reversed)
function ConvertTo-PackedGuid([string]$Guid) {
    $g = $Guid.Trim('{}').Replace('-', '')
    $rev = { param($s) -join ($s.ToCharArray()[($s.Length - 1)..0]) }
    $out  = & $rev $g.Substring(0, 8)
    $out += & $rev $g.Substring(8, 4)
    $out += & $rev $g.Substring(12, 4)
    for ($i = 16; $i -lt 32; $i += 2) { $out += $g[$i + 1]; $out += $g[$i] }
    return $out.ToUpper()
}

try {
    Write-Log "===== Start remediation for $ProductCode ====="

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        Write-Log "Key not present. Nothing to do."
        Write-Output "Key not present"
        exit 0
    }

    $p = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
    $label = "$($p.DisplayName) [$($p.DisplayVersion)] Publisher: $($p.Publisher)"
    Write-Log "Found: $label"
    Write-Log "UninstallString: $($p.UninstallString)  InstallLocation: $($p.InstallLocation)"

    # Is the MSI still registered with Windows Installer?
    $packed = ConvertTo-PackedGuid $ProductCode
    if (Test-Path "HKLM:\SOFTWARE\Classes\Installer\Products\$packed") {
        Write-Log "WARNING: Windows Installer still has this product registered (Installer\Products\$packed). The app may still be installed; removing the key only hides it from Apps & Features."
    }
    else {
        Write-Log "Windows Installer has no registration for this product - key is orphaned."
    }

    # Backup
    $backup = Join-Path $logDir ("Backup-{0}-{1}.reg" -f $ProductCode.Trim('{}'), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $r = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" `
         -ArgumentList 'export', "`"$RegExePath`"", "`"$backup`"", '/y', '/reg:64' -Wait -PassThru -WindowStyle Hidden
    Write-Log "Backup to $backup (reg.exe exit code $($r.ExitCode))"

    # Delete
    Remove-Item -LiteralPath $KeyPath -Recurse -Force
    if (Test-Path -LiteralPath $KeyPath) {
        Write-Log "FAILED: key still present after delete"
        Write-Output "Failed: key still present"
        exit 1
    }

    Write-Log "SUCCESS: removed $KeyPath"
    Write-Output "Success: removed uninstall key for $label"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Output "Error: $($_.Exception.Message)"
    exit 1
}