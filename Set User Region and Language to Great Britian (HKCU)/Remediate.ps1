# Exit 0 = compliant, Exit 1 = needs remediation
# Run as SYSTEM, 64-bit PowerShell (same settings as Remediate.ps1)

$Language      = 'en-GB'
$KeepLanguages = @()     # keep in sync with Remediate.ps1
$Issues        = @()

try {
    Import-Module LanguagePackManagement -ErrorAction Stop

    # Installed languages: en-GB present, nothing else
    $Installed = (Get-InstalledLanguage).LanguageId
    if ($Installed -notcontains $Language) { $Issues += "$Language not installed" }
    $Extra = $Installed | Where-Object { $_ -ne $Language -and $KeepLanguages -notcontains $_ }
    if ($Extra) { $Issues += "OtherLanguages=$($Extra -join ',')" }

    # Device display language and system locale
    $UiLang = Get-SystemPreferredUILanguage
    if ($UiLang -ne $Language) { $Issues += "SystemPreferredUILanguage=$UiLang" }

    $SysLocale = (Get-WinSystemLocale).Name
    if ($SysLocale -ne $Language) { $Issues += "SystemLocale=$SysLocale" }

    # Welcome screen (written together with the new-user default by Copy-UserInternationalSettingsToSystem)
    $Welcome = (Get-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International' -ErrorAction Stop).LocaleName
    if ($Welcome -ne $Language) { $Issues += "WelcomeScreenLocale=$Welcome" }
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}

if ($Issues.Count -gt 0) {
    Write-Output "Non-compliant: $($Issues -join '; ')"
    exit 1
}

Write-Output "Compliant: $Language only, set for device, welcome screen and new users"
exit 0
