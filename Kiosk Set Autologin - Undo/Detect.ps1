<#
.SYNOPSIS
    Detects if both AutoLogonCount and ForceAutoLogon registry values are set to 1.
.OUTPUTS
    Exit 0 = Compliant (No remediation needed)
    Exit 1 = Non-Compliant (Both values set to 1; remediation required)
#>

$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

# If path doesn't exist, values cannot be set to 1
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "Compliant: Registry path does not exist."
    Exit 0
}

# Fetch registry values
$AutoLogonCount = (Get-ItemProperty -LiteralPath $Path -Name 'AutoLogonCount' -ErrorAction SilentlyContinue).AutoLogonCount
$ForceAutoLogon = (Get-ItemProperty -LiteralPath $Path -Name 'ForceAutoLogon' -ErrorAction SilentlyContinue).ForceAutoLogon

# Check if both values are set to 1
$IsAutoLogonCountSet = ($AutoLogonCount -ne $null -and [string]$AutoLogonCount -eq '1')
$IsForceAutoLogonSet = ($ForceAutoLogon -ne $null -and [int]$ForceAutoLogon -eq 1)

if ($IsAutoLogonCountSet -and $IsForceAutoLogonSet) {
    Write-Output "Non-Compliant: Both AutoLogonCount and ForceAutoLogon are set to 1."
    Exit 1
} else {
    Write-Output "Compliant: AutoLogonCount and ForceAutoLogon are not both set to 1."
    Exit 0
}