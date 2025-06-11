try{
    Add-VpnConnection -Name "Name of VPN Client Connection" -ServerAddress "xxxx.domain.com" -TunnelType L2TP -L2tpPsk "Enter Password" -Force -AuthenticationMethod MSChapv2 -AllUserConnection -ErrorAction Stop
    exit 0
}
catch{
    $errMsg = $_.Exception.Message
    Write-host $errMsg
    exit 1
}