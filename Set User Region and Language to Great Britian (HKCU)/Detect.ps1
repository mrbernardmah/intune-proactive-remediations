<#
    Sets English (UK) as the device default and copies it to the welcome screen
    and new user accounts. Removes every other installed language.

    Intune remediation settings:
      - Run this script using the logged-on credentials: No  (runs as SYSTEM)
      - Run script in 64-bit PowerShell: Yes
    Requires Windows 11 22H2 or later (LanguagePackManagement module and
    Copy-UserInternationalSettingsToSystem). Install-Language needs access to
    Windows Update / Microsoft Update. System locale and language removals take
    full effect after a restart.
#>

$Language      = 'en-GB'
$GeoId         = 242     # United Kingdom
$KeepLanguages = @()     # language tags never to remove, e.g. @('en-US')

$LogDir  = "$env:ProgramData\Devicie\Logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = "$LogDir\SetLanguageToEnGB_$(Get-Date -Format yyyyMMdd_HHmmss).txt"
Start-Transcript -Path $LogFile | Out-Null

$Problems = @()

try {
    Import-Module LanguagePackManagement -ErrorAction Stop
    if (-not (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue)) {
        throw 'Copy-UserInternationalSettingsToSystem is not available (requires Windows 11 22H2 or later).'
    }

    # Record current state
    Write-Host '--- Current state ---'
    Get-InstalledLanguage | Out-String | Write-Host
    Write-Host "SystemPreferredUILanguage: $(Get-SystemPreferredUILanguage)"
    Write-Host "SystemLocale: $((Get-WinSystemLocale).Name)"

    # 1. Install the en-GB language pack and features if missing
    if ((Get-InstalledLanguage).LanguageId -notcontains $Language) {
        Write-Host "Installing $Language..."
        Install-Language -Language $Language -ErrorAction Stop | Out-Null
    }

    # 2. Device display language and system locale (non-Unicode programs)
    Set-SystemPreferredUILanguage -Language $Language -ErrorAction Stop
    Set-WinSystemLocale -SystemLocale $Language -ErrorAction Stop

    # 3. Set SYSTEM's own international settings, then copy them to the
    #    welcome screen and the default profile used for new user accounts
    Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language $Language) -Force
    Set-Culture -CultureInfo $Language
    Set-WinHomeLocation -GeoId $GeoId
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    # 4. Remove every other installed language (after en-GB is the display language)
    $ToRemove = Get-InstalledLanguage | Where-Object {
        $_.LanguageId -ne $Language -and $KeepLanguages -notcontains $_.LanguageId
    }
    foreach ($Lang in $ToRemove) {
        try {
            Write-Host "Removing $($Lang.LanguageId)..."
            Uninstall-Language -Language $Lang.LanguageId -ErrorAction Stop | Out-Null
        }
        catch {
            $Problems += "Remove $($Lang.LanguageId) failed: $($_.Exception.Message)"
        }
    }

    # 5. Verify
    $UiLang  = Get-SystemPreferredUILanguage
    $Welcome = (Get-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International' -ErrorAction SilentlyContinue).LocaleName
    if ($UiLang  -ne $Language) { $Problems += "SystemPreferredUILanguage=$UiLang" }
    if ($Welcome -ne $Language) { $Problems += "WelcomeScreenLocale=$Welcome" }

    if ($Problems.Count -eq 0) {
        Write-Output "Remediated: $Language set for device, welcome screen and new users; other languages removed (restart to complete)"
        $ExitCode = 0
    }
    else {
        Write-Output "Remediation incomplete: $($Problems -join '; ')"
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
