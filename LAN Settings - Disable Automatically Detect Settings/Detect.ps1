# Detection script: Non-compliant if "Automatically detect settings" is enabled or not set
$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$valueName = 'AutoDetect'

try {
    $value = (Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop).$valueName
    Write-Host "DEBUG: Found AutoDetect at $regPath : $value"
    if ([int]$value -eq 0) {
        Write-Host "AutoDetect is DISABLED. No remediation needed."
        Exit 0  # Compliant
    } else {
        Write-Host "AutoDetect is ENABLED. Remediation required."
        Exit 1  # Non-compliant
    }
} catch {
    Write-Host "DEBUG: AutoDetect not found at $regPath. Treating as ENABLED (non-compliant)."
    Write-Host "AutoDetect is ENABLED or not set. Remediation required."
    Exit 1  # Non-compliant
}