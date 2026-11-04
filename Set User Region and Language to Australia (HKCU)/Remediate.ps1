$LogDir  = "$env:LOCALAPPDATA\Devicie\Logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = "$LogDir\SetRegionToAustralia_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
Start-Transcript -Path $LogFile | Out-Null

try {
    # Record current state
    Get-Culture | Out-String | Write-Host
    Get-WinUserLanguageList | Out-String | Write-Host

    # 1. Language list: en-AU first, en-US secondary
    $LanguageList = New-WinUserLanguageList -Language 'en-AU'
    $LanguageList.Add('en-US')
    Set-WinUserLanguageList -LanguageList $LanguageList -Force

    # 2. Culture after language list so it isn't overridden
    Set-Culture -CultureInfo 'en-AU'
    Set-WinHomeLocation -GeoId 12

    # 3. Force explicit date formats
    $Intl = 'HKCU:\Control Panel\International'
    Set-ItemProperty -Path $Intl -Name sShortDate -Value 'dd/MM/yyyy'
    Set-ItemProperty -Path $Intl -Name sLongDate  -Value 'dddd, d MMMM yyyy'

    # Verify from registry (Get-Culture is cached in this session)
    $Reg = Get-ItemProperty -Path $Intl
    if ($Reg.LocaleName -eq 'en-AU' -and $Reg.sShortDate -eq 'dd/MM/yyyy') {
        Write-Output "Remediated: LocaleName=$($Reg.LocaleName), sShortDate=$($Reg.sShortDate)"
        $ExitCode = 0
    }
    else {
        Write-Output "Remediation incomplete: LocaleName=$($Reg.LocaleName), sShortDate=$($Reg.sShortDate)"
        $ExitCode = 1
    }
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    $ExitCode = 1
}
finally {
    Stop-Transcript | Out-Null
}

exit $ExitCode