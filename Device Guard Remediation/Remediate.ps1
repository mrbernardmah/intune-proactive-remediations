# Remediation Script for Device Guard / HVCI
$Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"

try {
    # Ensure key exists
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    # Set required registry values
    Set-ItemProperty -LiteralPath $Path -Name "RequirePlatformSecurityFeatures" -Value 3 -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -LiteralPath $Path -Name "HypervisorEnforcedCodeIntegrity" -Value 1 -Type DWord -Force -ErrorAction Stop
    Set-ItemProperty -LiteralPath $Path -Name "HVCIMATRequired" -Value 1 -Type DWord -Force -ErrorAction Stop

    Write-Output "Remediation Successful: DeviceGuard registry settings enforced."
    Exit 0
}
catch {
    Write-Error "Remediation Failed: $_"
    Exit 1
}