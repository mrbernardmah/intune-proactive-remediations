<#
.SYNOPSIS
Detection: exits 1 if winget reports an upgrade for any in-scope package.
.NOTES
Intune: Run this script using the logged-on credentials = No; Run script in 64-bit PowerShell = Yes.
Exit code 0 = compliant / succeeded, 1 = non-compliant / failed.
#>

[CmdletBinding()]
param()

# ============================== CONFIGURATION ==============================
# EDIT BEFORE DEPLOYING. Keep this block identical in Detect.ps1 and Remediate.ps1.
#
#   'All'      upgrade every package winget can upgrade (minus $ExcludeIds), including
#              packages that need explicit targeting, have an unreadable version,
#              carry a non-blocking pin, or show a truncated ID in winget's table
#   'Specific' upgrade only the packages listed in $AppIds
$UpgradeMode = 'All'

$AppIds = @(
    # 'Mozilla.Firefox'
    # 'Google.Chrome'
)

# Used when $UpgradeMode = 'All'. These self-update, so winget often fails on them.
$ExcludeIds = @(
    'Microsoft.Edge'
    'Microsoft.EdgeWebView2Runtime'
    'DisplayLink.GraphicsDriver'
)

$Source                 = 'winget'
$IncludeUnknownVersions = $true     # also upgrade apps whose installed version winget cannot read
$IncludePinned          = $true     # also upgrade apps with a non-blocking winget pin
$WingetTimeoutMinutes   = 30
# ===========================================================================

$ErrorActionPreference = 'Stop'

$ScriptName   = 'Winget-Upgrade'
$LogDirectory = Join-Path $env:ProgramData 'IntuneRemediation\Logs'
$LogFile      = Join-Path $LogDirectory 'Winget-Upgrade-Detect.log'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION', 'DRYRUN', 'BLOCKED', 'SUCCESS', 'COMPLIANT', 'NON-COMPLIANT')]
        [string]$Level = 'INFO'
    )

    $line = "[$Level] $Message"

    # Write-Host (not Write-Output) so helper functions can still return clean values.
    Write-Host $line

    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $line) -ErrorAction Stop
    }
    catch {
        # Logging must never break detection/remediation.
    }
}

function Test-IsWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return $true
    }

    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
}

function Test-IsSystemOrAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return (
        $identity.IsSystem -or
        $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    )
}

function Format-ShortList {
    param(
        [string[]]$Items,
        [int]$MaxLength = 1500
    )

    $text = ($Items -join '; ')
    if ($text.Length -gt $MaxLength) {
        $text = $text.Substring(0, $MaxLength) + '... (truncated, see log file)'
    }

    return $text
}

function Exit-Compliant {
    param([string]$Message)

    Write-Log -Level 'COMPLIANT' -Message $Message
    exit 0
}

function Exit-NonCompliant {
    param([string]$Message)

    Write-Log -Level 'NON-COMPLIANT' -Message $Message
    exit 1
}

# winget exit codes (HRESULTs as signed Int32).
$WingetExit = @{
    NoApplicationsFound   = -1978335212   # 0x8A150014 - no installed package matched
    NoApplicableInstaller = -1978335216   # 0x8A150010 - e.g. requested scope not offered
    UpdateNotApplicable   = -1978335189   # 0x8A15002B - nothing newer available
    AlreadyInstalled      = -1978335135   # 0x8A150061
}

function Get-WingetPath {
    # Under LocalSystem winget is not on PATH; resolve the newest App Installer package instead.
    $pattern = Join-Path $env:ProgramFiles 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe'
    $candidates = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)

    if ($candidates.Count -gt 0) {
        $newest = $candidates | Sort-Object -Descending -Property @{
            Expression = {
                try { [version](($_.Directory.Name -split '_')[1]) } catch { [version]'0.0' }
            }
        } | Select-Object -First 1

        return $newest.FullName
    }

    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)

    $parts = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') {
            '"{0}"' -f ($argument -replace '"', '\"')
        }
        else {
            $argument
        }
    }

    return ($parts -join ' ')
}

function Invoke-Winget {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [int]$TimeoutMinutes = 30
    )

    $token = [guid]::NewGuid().ToString('N')
    $stdoutFile = Join-Path $env:TEMP "winget-$token.out"
    $stderrFile = Join-Path $env:TEMP "winget-$token.err"
    $timedOut = $false

    try {
        $process = Start-Process -FilePath $WingetPath `
            -ArgumentList (ConvertTo-ArgumentString -Arguments $Arguments) `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $null = $process.Handle   # cache the handle so ExitCode is reliable

        if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null
        }
        else {
            $process.WaitForExit()
        }

        $text = ''
        foreach ($file in @($stdoutFile, $stderrFile)) {
            if (Test-Path -LiteralPath $file) {
                $text += (Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
            }
        }

        $exitCode = -1
        if (-not $timedOut) { $exitCode = [int]$process.ExitCode }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = [string]$text
            TimedOut = $timedOut
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Update-WingetSources {
    # A fresh LocalSystem profile has no source index yet; refresh it once (best effort).
    $result = Invoke-Winget -Arguments @('source', 'update', '--disable-interactivity') -TimeoutMinutes 5
    if ($result.TimedOut -or $result.ExitCode -ne 0) {
        Write-Log -Level 'WARN' -Message "winget source update returned exit code $($result.ExitCode)$(if ($result.TimedOut) { ' (timed out)' }). Continuing."
    }
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Id)

    $result = Invoke-Winget -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') -TimeoutMinutes 5

    if ($result.TimedOut) {
        throw "winget list timed out while checking '$Id'."
    }

    if ($result.ExitCode -eq $WingetExit.NoApplicationsFound -or $result.Output -match '(?i)No installed package found') {
        return $false
    }

    if ($result.ExitCode -ne 0) {
        throw "winget list failed for '$Id' with exit code $($result.ExitCode)."
    }

    return $true
}

function Get-AppSetting {
    # Reads an optional key from an app hashtable, falling back to a default.
    param(
        [hashtable]$App,
        [string]$Key,
        [string]$Default = ''
    )

    if ($App.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$App[$Key])) {
        return [string]$App[$Key]
    }

    return $Default
}

function ConvertFrom-WingetUpgradeTable {
    # Pulls package IDs out of the table printed by `winget upgrade`.
    param([string]$Text)

    $ids = New-Object System.Collections.Generic.List[string]
    $sawHeader = $false
    $inTable = $false
    $idStart = 0
    $versionStart = 0

    foreach ($rawLine in ($Text -split "`r?`n")) {
        # Progress spinners overwrite the line with carriage returns; keep the last segment.
        $line = @($rawLine -split "`r")[-1]

        # Packages after the "require explicit targeting" marker sit in a second table with
        # the same header. They are kept: each upgrade below targets its package by --id.

        if (-not $inTable) {
            if ($line -match '^\s*Name\s+Id\s+Version\s+Available') {
                $idStart = [regex]::Match($line, '\sId\s').Index + 1
                $versionStart = [regex]::Match($line, '\sVersion\s').Index + 1
                $sawHeader = $true
            }
            elseif ($sawHeader -and $line -match '^-{3,}\s*$') {
                $inTable = $true
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*\d+\s+upgrades?\s+available') {
            $inTable = $false
            $sawHeader = $false
            continue
        }

        if ($line.Length -gt $versionStart) {
            $id = $line.Substring($idStart, $versionStart - $idStart).Trim()
            if ($id) { $ids.Add($id) }
        }
    }

    return @($ids)
}

function Get-ExportedPackageIds {
    # Full IDs of every installed package that maps to $Source, from `winget export`.
    # Used to expand IDs that winget truncated in its upgrade table.
    $exportFile = Join-Path $env:TEMP ('winget-export-{0}.json' -f [guid]::NewGuid().ToString('N'))

    try {
        $exportArgs = @('export', '--output', $exportFile, '--source', $Source,
                        '--accept-source-agreements', '--disable-interactivity')
        $result = Invoke-Winget -Arguments $exportArgs -TimeoutMinutes 10

        # winget export exits non-zero when some installed apps have no source match,
        # but still writes the file, so the file is what counts.
        if (-not (Test-Path -LiteralPath $exportFile)) {
            Write-Log -Level 'WARN' -Message "winget export wrote no file (exit code $($result.ExitCode)). Truncated IDs cannot be resolved."
            return @()
        }

        $json = Get-Content -LiteralPath $exportFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return @(
            @($json.Sources) | ForEach-Object { @($_.Packages) } |
                ForEach-Object { [string]$_.PackageIdentifier } |
                Where-Object { $_ } | Sort-Object -Unique
        )
    }
    catch {
        Write-Log -Level 'WARN' -Message "Could not read winget export: $($_.Exception.Message)"
        return @()
    }
    finally {
        Remove-Item -LiteralPath $exportFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-TruncatedId {
    # Returns the single full ID that starts with the truncated prefix, or $null.
    param(
        [string]$TruncatedId,
        [string[]]$KnownIds
    )

    $prefix = $TruncatedId.TrimEnd([char]0x2026).TrimEnd('.').Trim()
    if (-not $prefix) { return $null }

    $found = @($KnownIds | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($found.Count -eq 1) { return $found[0] }

    return $null
}

function Get-UpgradeCandidates {
    # Returns the package IDs that currently have an upgrade available and are in scope.
    $baseArgs = @('--source', $Source, '--accept-source-agreements', '--disable-interactivity')
    if ($IncludeUnknownVersions) { $baseArgs += '--include-unknown' }
    if ($IncludePinned)          { $baseArgs += '--include-pinned' }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($UpgradeMode -eq 'Specific') {
        foreach ($id in $AppIds) {
            $result = Invoke-Winget -Arguments (@('upgrade', '--id', $id, '--exact') + $baseArgs) -TimeoutMinutes 10

            if ($result.TimedOut) {
                throw "winget upgrade query timed out for '$id'."
            }

            if ($result.ExitCode -eq $WingetExit.NoApplicationsFound -or
                $result.ExitCode -eq $WingetExit.UpdateNotApplicable -or
                $result.Output -match '(?i)No (available upgrade|installed package|newer package)') {
                continue
            }

            if ($result.ExitCode -ne 0) {
                Write-Log -Level 'WARN' -Message "winget upgrade query for $id returned exit code $($result.ExitCode). Skipping."
                continue
            }

            if ($result.Output -match '(?im)\bAvailable\b') {
                $candidates.Add([string]$id)
            }
        }

        return @($candidates)
    }

    $result = Invoke-Winget -Arguments (@('upgrade') + $baseArgs) -TimeoutMinutes 10
    if ($result.TimedOut) {
        throw 'winget upgrade query timed out.'
    }

    $ids = @(ConvertFrom-WingetUpgradeTable -Text $result.Output)

    # Safety net: winget says upgrades exist but the table could not be read (e.g. non-English headers).
    if ($ids.Count -eq 0 -and $result.Output -match '(?im)^\s*[1-9]\d*\s+upgrades?\s+available') {
        throw 'winget reported available upgrades but the package table could not be parsed.'
    }

    $ellipsis = [string][char]0x2026
    $exportedIds = $null
    foreach ($id in $ids) {
        if ($id.EndsWith($ellipsis) -or $id.EndsWith('...')) {
            if ($null -eq $exportedIds) { $exportedIds = @(Get-ExportedPackageIds) }

            $fullId = Resolve-TruncatedId -TruncatedId $id -KnownIds $exportedIds
            if (-not $fullId) {
                Write-Log -Level 'WARN' -Message "Could not resolve truncated package ID '$id' to a single package. Skipping it."
                continue
            }

            Write-Log "Resolved truncated ID '$id' to '$fullId'."
            $id = $fullId
        }

        if ($ExcludeIds -contains $id) {
            Write-Log "Excluded by configuration: $id"
            continue
        }

        if (-not $candidates.Contains($id)) { $candidates.Add($id) }
    }

    return @($candidates)
}

# Relaunch in 64-bit Windows PowerShell if Intune started us in a 32-bit host.
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $sysnativePowerShell = Join-Path $env:WINDIR 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $sysnativePowerShell) {
        & $sysnativePowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

try {
    Write-Log "Starting winget upgrade detection (mode: $UpgradeMode)."

    if (-not (Test-IsWindows)) {
        Exit-NonCompliant 'This script must run on Windows.'
    }

    if (-not (Test-IsSystemOrAdmin)) {
        Exit-NonCompliant 'This script must run as LocalSystem or local administrator. In Intune, set "Run this script using the logged-on credentials" to "No".'
    }

    if ($UpgradeMode -notin @('All', 'Specific')) {
        Exit-NonCompliant "Invalid `$UpgradeMode '$UpgradeMode'. Use 'All' or 'Specific'."
    }

    if ($UpgradeMode -eq 'Specific' -and @($AppIds).Count -eq 0) {
        Exit-Compliant "`$UpgradeMode is 'Specific' but `$AppIds is empty."
    }

    $WingetPath = Get-WingetPath
    if (-not $WingetPath) {
        Exit-NonCompliant 'winget.exe was not found. Cannot check for upgrades.'
    }
    Write-Log "Using winget at: $WingetPath"

    Update-WingetSources

    $pending = @(Get-UpgradeCandidates)
    if ($pending.Count -gt 0) {
        Exit-NonCompliant "$($pending.Count) upgrade(s) available: $(Format-ShortList -Items $pending)"
    }

    Exit-Compliant 'No upgrades are available for the in-scope packages.'
}
catch {
    Write-Log -Level 'ERROR' -Message "Detection failed: $($_.Exception.Message)"
    exit 1
}s