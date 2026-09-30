<#
.SYNOPSIS
    Detection Script - Remove Custom Lockscreen Settings
.DESCRIPTION
    Checks if PersonalizationCSP lock screen registry values exist.
    Exits with 1 (Non-Compliant) if found to trigger remediation.
#>

$LockScreenPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

if (Test-Path -Path $LockScreenPath) {
    $props = Get-ItemProperty -Path $LockScreenPath -ErrorAction SilentlyContinue

    # Check if any of the target properties exist
    $hasImagePath  = $null -ne $props.LockScreenImagePath
    $hasImageUrl   = $null -ne $props.LockScreenImageUrl
    $hasImageStatus = $null -ne $props.LockScreenImageStatus

    if ($hasImagePath -or $hasImageUrl -or $hasImageStatus) {
        Write-Output "NON-COMPLIANT: Custom lock screen registry values exist. Remediation required."
        Exit 1
    } else {
        Write-Output "COMPLIANT: Lock screen values are not present."
        Exit 0
    }
} else {
    Write-Output "COMPLIANT: PersonalizationCSP registry key does not exist."
    Exit 0
}