# Exit 0 = compliant, Exit 1 = needs remediation
$Intl   = 'HKCU:\Control Panel\International'
$Issues = @()

try {
    $Reg = Get-ItemProperty -Path $Intl -ErrorAction Stop

    if ($Reg.LocaleName -ne 'de-DE')        { $Issues += "LocaleName=$($Reg.LocaleName)" }
    if ($Reg.sShortDate -ne 'dd.MM.yyyy')   { $Issues += "sShortDate=$($Reg.sShortDate)" }

    $LangList  = Get-WinUserLanguageList
    $FirstLang = $LangList[0].LanguageTag
    if ($FirstLang -ne 'de-DE')             { $Issues += "FirstLanguage=$FirstLang" }

    if (-not ($LangList | Where-Object { $_.LanguageTag -eq 'en-GB' })) {
        $Issues += "SecondaryLanguage en-GB missing"
    }

    $Override = (Get-WinDefaultInputMethodOverride).InputMethodTip
    if ($Override -ne '0407:00000407')      { $Issues += "DefaultKeyboard=$Override" }

    $GeoId = (Get-WinHomeLocation).GeoId
    if ($GeoId -ne 94)                      { $Issues += "GeoId=$GeoId" }
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}

if ($Issues.Count -gt 0) {
    Write-Output "Non-compliant: $($Issues -join '; ')"
    exit 1
}

Write-Output "Compliant: de-DE, German keyboard, en-GB secondary, dd.MM.yyyy"
exit 0
