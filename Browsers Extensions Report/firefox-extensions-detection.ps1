<#
.SYNOPSIS
    Intune detection script – Unauthorized Firefox Extensions Report.

.DESCRIPTION
    Scans all user profiles for Firefox extensions not present in AllowedIds.
    Outputs JSON to stdout for Intune and writes a detailed report to IME Logs folder.

.NOTES
    Exit 0 = Compliant, Exit 1 = Non-compliant
#>

# ==============================================================
# CONFIGURATION – edit before deployment
# ==============================================================

$AllowedIds = @()
$LogPath = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs"
$JsonFile = "FirefoxExtensions-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ==============================================================
# FUNCTIONS – local script functions
# ==============================================================

function Read-JsonFile {
    <#
    .SYNOPSIS
        Safely reads and deserializes a JSON file.
    .OUTPUTS
        Deserialized object or $null on failure.
    #>
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-UserProfiles {
    <#
    .SYNOPSIS
        Returns local user profile directories, excluding system accounts.
    #>
    Get-ChildItem "C:\Users" -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer -and $_.Name -notin @("Public", "Default", "Default User", "All Users") }
}

# ==============================================================
# MAIN – script core
# ==============================================================

$allExtensions = @()
$browserDetected = $false

Get-UserProfiles | ForEach-Object {
    $userName = $_.Name
    $ffRoot = Join-Path $_.FullName "AppData\Roaming\Mozilla\Firefox\Profiles"
    if (-not (Test-Path $ffRoot)) { return }

    $script:browserDetected = $true

    Get-ChildItem -Path $ffRoot -Filter "extensions.json" -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
        $extJson = Read-JsonFile $_.FullName
        if (-not ($extJson -and $extJson.addons)) { return }

        foreach ($addon in $extJson.addons) {
            if ($addon.type -eq "extension" -and $addon.id) {

                $installDate = if ($addon.installDate) {
                    [DateTimeOffset]::FromUnixTimeMilliseconds($addon.installDate).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
                else {
                    $null
                }

                $allExtensions += [PSCustomObject]@{
                    Browser     = "Mozilla Firefox"
                    User        = $userName
                    Profile     = $_.Directory.Name
                    Id          = $addon.id
                    Name        = $addon.defaultLocale.name
                    Version     = $addon.version
                    InstallDate = $installDate
                    Enabled     = [bool]$addon.active
                }
            }
        }
    }
}

$AllowedIds = $AllowedIds | ForEach-Object { $_.Trim().ToLower() }

$unauthorizedExts = $allExtensions |
Where-Object { $_.Id.ToLower() -notin $AllowedIds }

[string[]]$unauthorizedIds = @(
    $unauthorizedExts | Select-Object -ExpandProperty Id -Unique
)

$report = [ordered]@{
    Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    BrowserDetected = $browserDetected
    Summary         = [ordered]@{
        TotalExtensions = $allExtensions.Count
        Unauthorized    = $unauthorizedIds.Count
        Total           = $allExtensions.Count
    }
    Unauthorized    = $unauthorizedExts
}
$report | ConvertTo-Json -Depth 5 |
Out-File (Join-Path $LogPath $JsonFile) -Encoding UTF8 -Force

[ordered]@{
    UnauthorizedCount = $unauthorizedIds.Count
    UnauthorizedIds   = $unauthorizedIds
} | ConvertTo-Json -Compress | Write-Output

if ($unauthorizedIds.Count -gt 0) { exit 1 } else { exit 0 }
