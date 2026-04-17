<#
.SYNOPSIS
    Intune detection script – Unauthorized Google Chrome Extensions Report.

.DESCRIPTION
    Scans all user profiles for Google Chrome extensions not present in AllowedIds.
    Outputs JSON to stdout for Intune and writes a detailed report to IME Logs folder.

.NOTES
    Exit 0 = Compliant, Exit 1 = Non-compliant
#>

# ==============================================================
# CONFIGURATION – edit before deployment
# ==============================================================

$AllowedIds = @()
$LogPath = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs"
$JsonFile = "ChromeExtensions-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
    $chromeRoot = Join-Path $_.FullName "AppData\Local\Google\Chrome\User Data"
    if (-not (Test-Path $chromeRoot)) { return }

    $script:browserDetected = $true

    Get-ChildItem -Path $chromeRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "Default" -or $_.Name -match "^Profile \d+$" } |
    ForEach-Object {
        $profilePath = [IO.Path]::GetFullPath($_.FullName)
        $profileName = $_.Name
        $extensionsDir = Join-Path $profilePath "Extensions"
        if (-not (Test-Path $extensionsDir)) { return }

        Get-ChildItem -Path $extensionsDir -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $extId = $_.Name
            $extDir = $_.FullName

            $versionDir = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            Select-Object -First 1

            if (-not $versionDir) { return }

            $manifest = Read-JsonFile (Join-Path $versionDir.FullName "manifest.json")
            if (-not ($manifest -and $manifest.name)) { return }
            
            # Exclude themes
            if ($manifest.theme) { return }

            $allExtensions += [PSCustomObject]@{
                Browser     = "Google Chrome"
                User        = $userName
                Profile     = $profileName
                Id          = $extId
                Name        = $manifest.name
                Version     = $manifest.version
                InstallDate = $_.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                Enabled     = "Not supported"
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
