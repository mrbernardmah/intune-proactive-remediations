<#
.SYNOPSIS
    Remediation script: enables Fast Startup (Hiberboot).
.DESCRIPTION
    Turns hibernation on if it is off (Fast Startup depends on it), then sets
    HiberbootEnabled = 1 (DWORD). Takes effect from the next shutdown.
    Exit 0 = success, exit 1 = failure.
    Run as SYSTEM in 64-bit PowerShell.
#>

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$ValueName    = "HiberbootEnabled"
$TargetValue  = 1

try {
    # Ensure hibernation is enabled (creates hiberfil.sys if needed)
    $PowerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
    $HibernateEnabled = (Get-ItemProperty -Path $PowerPath -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
    if ($HibernateEnabled -eq 0) {
        & powercfg.exe /hibernate on
        if ($LASTEXITCODE -ne 0) {
            Write-Output "Failed: powercfg /hibernate on returned $LASTEXITCODE."
            exit 1
        }
    }

    if (-not (Test-Path -Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $RegistryPath -Name $ValueName -Value $TargetValue `
        -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    # Verify the change
    $NewValue = Get-ItemPropertyValue -Path $RegistryPath -Name $ValueName -ErrorAction Stop
    if ($NewValue -eq $TargetValue) {
        Write-Output "Remediated: Fast Startup enabled ($ValueName = $NewValue)."
        exit 0
    }
    else {
        Write-Output "Failed: $ValueName is $NewValue after write, expected $TargetValue."
        exit 1
    }
}
catch {
    Write-Output "Failed to enable Fast Startup: $($_.Exception.Message)"
    exit 1
}