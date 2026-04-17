<#
.SYNOPSIS
    Intune detection script – Browser Sync / Personal Account Report.
.DESCRIPTION
    Scans Edge, Chrome, and Firefox for signed-in profiles with Sync enabled.
    Outputs account details and returns Exit 1 if unauthorized sync is detected.
#>

$LogPath = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs"
$JsonFile = "BrowserSyncReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# --- Functions ---
function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
}

function Get-UserProfiles {
    Get-ChildItem "C:\Users" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer -and $_.Name -notin @("Public", "Default", "Default User", "All Users") }
}

# --- Main Scraper ---
$SyncReport = @()

Get-UserProfiles | ForEach-Object {
    $userName = $_.Name
    $userPath = $_.FullName

    # 1. Chromium (Edge & Chrome)
    $Browsers = @{
        "Edge"   = "AppData\Local\Microsoft\Edge\User Data"
        "Chrome" = "AppData\Local\Google\Chrome\User Data"
    }

    foreach ($bName in $Browsers.Keys) {
        $path = Join-Path $userPath $Browsers[$bName]
        if (Test-Path $path) {
            # Search for 'Preferences' files in all profiles (Default, Profile 1, etc.)
            Get-ChildItem -Path $path -Filter "Preferences" -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
                $pref = Read-JsonFile $_.FullName
                $email = $pref.account_info.email # Primary for modern Edge/Chrome
                if (-not $email) { $email = $pref.google.services.signin.user_display_name }

                if ($email) {
                    $SyncReport += [PSCustomObject]@{
                        User    = $userName
                        Browser = $bName
                        Account = $email
                        SyncOn  = $true
                    }
                }
            }
        }
    }

    # 2. Firefox
    $ffRoot = Join-Path $userPath "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (Test-Path $ffRoot) {
        Get-ChildItem -Path $ffRoot -Filter "signedInUser.json" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $ffUser = Read-JsonFile $_.FullName
            if ($ffUser -and $ffUser.email) {
                $SyncReport += [PSCustomObject]@{
                    User    = $userName
                    Browser = "Firefox"
                    Account = $ffUser.email
                    SyncOn  = $true
                }
            }
        }
    }
}

# --- Reporting ---
$ReportObj = [ordered]@{
    Timestamp     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    TotalSignedOn = $SyncReport.Count
    Details       = $SyncReport
}

$ReportObj | ConvertTo-Json -Depth 4 | Out-File (Join-Path $LogPath $JsonFile) -Encoding UTF8 -Force

# Intune Output
Write-Output ($ReportObj | ConvertTo-Json -Compress)

# Exit logic: Exit 1 (Non-compliant) if any signed-in users are found
if ($SyncReport.Count -gt 0) { exit 1 } else { exit 0 }