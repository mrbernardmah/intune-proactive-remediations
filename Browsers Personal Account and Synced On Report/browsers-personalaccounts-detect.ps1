<#
.SYNOPSIS
    Intune detection script – Personal Browser Account Sign-in Report.
.DESCRIPTION
    Scans Edge, Chrome, and Firefox profiles to identify signed-in personal accounts.
    Outputs account emails to stdout and logs a detailed report.
#>

$LogPath = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs"
$JsonFile = "BrowserSignIns-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Get-UserProfiles {
    Get-ChildItem "C:\Users" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer -and $_.Name -notin @("Public", "Default", "Default User", "All Users") }
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }
}

$AccountReport = @()

Get-UserProfiles | ForEach-Object {
    $userName = $_.Name
    $userPath = $_.FullName

    # --- 1. Edge & Chrome (Chromium based) ---
    $ChromiumBrowsers = @{
        "Edge"   = "AppData\Local\Microsoft\Edge\User Data"
        "Chrome" = "AppData\Local\Google\Chrome\User Data"
    }

    foreach ($browser in $ChromiumBrowsers.Keys) {
        $path = Join-Path $userPath $ChromiumBrowsers[$browser]
        if (Test-Path $path) {
            # Chromium stores preferences in 'Default' or 'Profile X' folders
            $prefFiles = Get-ChildItem -Path $path -Filter "Preferences" -Recurse -Depth 2 -ErrorAction SilentlyContinue
            foreach ($file in $prefFiles) {
                $data = Read-JsonFile $file.FullName
                # Looking for the 'account_info' or 'google.services.signin' sync data
                $email = $data.account_info.email # Newer Edge/Chrome
                if (-not $email) { $email = $data.google.services.signin.user_display_name } # Older Chrome

                if ($email) {
                    $AccountReport += [PSCustomObject]@{
                        User    = $userName
                        Browser = $browser
                        Email   = $email
                        Type    = if ($email -match "(@gmail\.com|@outlook\.com|@hotmail\.com|@live\.com|@icloud\.com)") { "Personal" } else { "Work/Other" }
                    }
                }
            }
        }
    }

    # --- 2. Mozilla Firefox ---
    $ffRoot = Join-Path $userPath "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $ffRoot) {
        $signedInFiles = Get-ChildItem -Path $ffRoot -Filter "signedInUser.json" -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $signedInFiles) {
            $data = Read-JsonFile $file.FullName
            if ($data -and $data.email) {
                $AccountReport += [PSCustomObject]@{
                    User    = $userName
                    Browser = "Firefox"
                    Email   = $data.email
                    Type    = if ($data.email -match "(@gmail\.com|@outlook\.com|@hotmail\.com|@live\.com|@icloud\.com)") { "Personal" } else { "Work/Other" }
                }
            }
        }
    }
}

# Filter for just Personal accounts if that is the priority
$PersonalAccounts = $AccountReport | Where-Object { $_.Type -eq "Personal" }

# Log detailed report
$PersonalAccounts | ConvertTo-Json | Out-File (Join-Path $LogPath $JsonFile) -Encoding UTF8 -Force

# Output for Intune (Non-compliant if personal accounts are found)
[ordered]@{
    PersonalAccountCount = $PersonalAccounts.Count
    AccountsFound        = $PersonalAccounts.Email
} | ConvertTo-Json -Compress | Write-Output

if ($PersonalAccounts.Count -gt 0) { exit 1 } else { exit 0 }