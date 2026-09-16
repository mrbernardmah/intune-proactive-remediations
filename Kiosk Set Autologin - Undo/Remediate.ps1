<#
.SYNOPSIS
    Deletes AutoLogonCount and ForceAutoLogon registry values.
.OUTPUTS
    Exit 0 = Remediation successful
    Exit 1 = Remediation failed
#>

$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

try {
    if (Test-Path -LiteralPath $Path) {
        Remove-ItemProperty -LiteralPath $Path -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath $Path -Name 'ForceAutoLogon' -ErrorAction SilentlyContinue
    }

    Write-Output "Remediation Successful: Deleted AutoLogonCount and ForceAutoLogon registry values."
    Exit 0
}
catch {
    Write-Error "Remediation Failed: $($_.Exception.Message)"
    Exit 1
}