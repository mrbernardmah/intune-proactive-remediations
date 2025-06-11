[CmdletBinding()]
Param (
)
$ConnectionName = 'Name of VPN Connection Profile'
$Vpn = Get-VpnConnection -Name $ConnectionName -AllUserConnection -ErrorAction SilentlyContinue
Try {
    If ($Null -eq $Vpn) {
        Write-Warning "VPN connection `'$ConnectionName`' not found."
        Exit 0
    }
    Write-Verbose "Removing VPN connection `'$ConnectionName`'..."
    Get-VpnConnection -Name $ConnectionName -AllUserConnection | Remove-VpnConnection -Force
}
Catch {
    $ErrorMessage = $_.Exception.Message
    Write-Warning $ErrorMessage
    Exit 1
}