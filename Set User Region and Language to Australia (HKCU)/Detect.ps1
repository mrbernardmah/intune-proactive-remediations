# Exit 0 = compliant, Exit 1 = needs remediation
$Intl  = 'HKCU:\Control Panel\International'
$Issues = @()

try {
    $Reg = Get-ItemProperty -Path $Intl -ErrorAction Stop

    if ($Reg.LocaleName -ne 'en-AU')        { $Issues += "LocaleName=$($Reg.LocaleName)" }
    if ($Reg.sShortDate -ne 'dd/MM/yyyy')   { $Issues += "sShortDate=$($Reg.sShortDate)" }

    $FirstLang = (Get-WinUserLanguageList)[0].LanguageTag
    if ($FirstLang -ne 'en-AU')             { $Issues += "FirstLanguage=$FirstLang" }

    $GeoId = (Get-WinHomeLocation).GeoId
    if ($GeoId -ne 12)                      { $Issues += "GeoId=$GeoId" }
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}

if ($Issues.Count -gt 0) {
    Write-Output "Non-compliant: $($Issues -join '; ')"
    exit 1
}

Write-Output "Compliant: en-AU, dd/MM/yyyy"
exit 0s