<#
.SYNOPSIS
    Detects if AutoLogonCount and ForceAutoLogon registry settings are compliant.
.OUTPUTS
    Exit 0 = Compliant (No remediation needed)
    Exit 1 = Non-Compliant (Remediation required)
#>

$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

# Check registry path existence
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "Non-Compliant: Registry path does not exist."
    Exit 1
}

# Fetch registry values
$AutoLogonCount = (Get-ItemProperty -LiteralPath $Path -Name 'AutoLogonCount' -ErrorAction SilentlyContinue).AutoLogonCount
$ForceAutoLogon = (Get-ItemProperty -LiteralPath $Path -Name 'ForceAutoLogon' -ErrorAction SilentlyContinue).ForceAutoLogon

# Validate values
$IsAutoLogonCountCompliant = ($AutoLogonCount -ne $null -and [string]$AutoLogonCount -eq '1')
$IsForceAutoLogonCompliant = ($ForceAutoLogon -ne $null -and [int]$ForceAutoLogon -eq 1)

if ($IsAutoLogonCountCompliant -and $IsForceAutoLogonCompliant) {
    Write-Output "Compliant: AutoLogonCount and ForceAutoLogon are configured correctly."
    Exit 0
} else {
    Write-Output "Non-Compliant: One or both registry values are missing or incorrect."
    Exit 1
}