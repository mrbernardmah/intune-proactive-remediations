<#
.SYNOPSIS
    Remediation script: disables Fast Startup (Hiberboot).
.DESCRIPTION
    Sets HiberbootEnabled = 0 (DWORD). Hibernation itself is left alone.
    Takes effect from the next shutdown; no reboot needed.
    Exit 0 = success, exit 1 = failure.
    Run as SYSTEM in 64-bit PowerShell.
#>

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
$ValueName    = "HiberbootEnabled"
$TargetValue  = 0

try {
    if (-not (Test-Path -Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $RegistryPath -Name $ValueName -Value $TargetValue `
        -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    # Verify the change
    $NewValue = Get-ItemPropertyValue -Path $RegistryPath -Name $ValueName -ErrorAction Stop
    if ($NewValue -eq $TargetValue) {
        Write-Output "Remediated: Fast Startup disabled ($ValueName = $NewValue)."
        exit 0
    }
    else {
        Write-Output "Failed: $ValueName is $NewValue after write, expected $TargetValue."
        exit 1
    }
}
catch {
    Write-Output "Failed to set $ValueName : $($_.Exception.Message)"
    exit 1
}