try{
    if (Get-VpnConnection -AllUserConnection -Name "Name of VPN Client Connection" -ErrorAction Stop)
    {
        write-host "Success"
        exit 0  
    }
  
}
catch{
    $errMsg = $_.Exception.Message
    write-host $errMsg
    exit 1
}