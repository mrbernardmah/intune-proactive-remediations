$LogDir  = "$env:LOCALAPPDATA\Devicie\Logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = "$LogDir\SetRegionToGermany_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
Start-Transcript -Path $LogFile | Out-Null

try {
    # Record current state
    Get-Culture | Out-String | Write-Host
    Get-WinUserLanguageList | Out-String | Write-Host

    # 1. Language list: de-DE first (German keyboard 0407), en-GB secondary (UK keyboard 0809)
    $LanguageList = New-WinUserLanguageList -Language 'de-DE'
    $LanguageList.Add('en-GB')
    Set-WinUserLanguageList -LanguageList $LanguageList -Force

    # 2. Force German keyboard as the default input method
    Set-WinDefaultInputMethodOverride -InputTip '0407:00000407'

    # 3. Culture after language list so it isn't overridden; home location Germany
    Set-Culture -CultureInfo 'de-DE'
    Set-WinHomeLocation -GeoId 94

    # 4. Force explicit German date formats
    $Intl = 'HKCU:\Control Panel\International'
    Set-ItemProperty -Path $Intl -Name sShortDate -Value 'dd.MM.yyyy'
    Set-ItemProperty -Path $Intl -Name sLongDate  -Value 'dddd, d. MMMM yyyy'

    # Verify from registry (Get-Culture is cached in this session)
    $Reg       = Get-ItemProperty -Path $Intl
    $FirstLang = (Get-WinUserLanguageList)[0].LanguageTag
    $Override  = (Get-WinDefaultInputMethodOverride).InputMethodTip

    if ($Reg.LocaleName -eq 'de-DE' -and
        $Reg.sShortDate -eq 'dd.MM.yyyy' -and
        $FirstLang -eq 'de-DE' -and
        $Override -eq '0407:00000407') {
        Write-Output "Remediated: LocaleName=$($Reg.LocaleName), sShortDate=$($Reg.sShortDate), FirstLanguage=$FirstLang, Keyboard=$Override"
        $ExitCode = 0
    }
    else {
        Write-Output "Remediation incomplete: LocaleName=$($Reg.LocaleName), sShortDate=$($Reg.sShortDate), FirstLanguage=$FirstLang, Keyboard=$Override"
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
