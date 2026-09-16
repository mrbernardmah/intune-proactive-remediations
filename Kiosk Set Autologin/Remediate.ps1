<#
.SYNOPSIS
    Configures AutoLogonCount and ForceAutoLogon registry values.
.OUTPUTS
    Exit 0 = Remediation successful
    Exit 1 = Remediation failed
#>

$Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

try {
    # Ensure path exists
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }

    # Set AutoLogonCount (String)
    New-ItemProperty -LiteralPath $Path -Name "AutoLogonCount" -Value "1" -PropertyType String -Force -ErrorAction Stop | Out-Null

    # Set ForceAutoLogon (DWORD)
    New-ItemProperty -LiteralPath $Path -Name "ForceAutoLogon" -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    Write-Output "Remediation Successful: Set AutoLogonCount to '1' (String) and ForceAutoLogon to 1 (DWORD)."
    Exit 0
}
catch {
    Write-Error "Remediation Failed: $($_.Exception.Message)"
    Exit 1
}