[CmdletBinding()]
Param (
)
$ConnectionName = 'Name of VPN Connection Profile'
$Vpn = Get-VPnConnection -Name $ConnectionName -AllUserConnection -ErrorAction SilentlyContinue
Try {
    If ($Null -eq $Vpn) {
        Write-Warning "VPN connection `'$ConnectionName`' not found."
        Exit 0
    }
    Else {
        Write-Verbose "VPN connection name matching `'$ConnectionName`' found. Remediation required."
        Exit 1
    }
}
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Warning $ErrorMessage
    Exit 1
}