<#
.SYNOPSIS
    Intune Remediations - DETECTION script for Microsoft .NET Runtime 10 (x64).

.DESCRIPTION
    Exit 0 = compliant (latest .NET 10 runtime patch installed, or not installed and not required)
    Exit 1 = non-compliant (remediation will run)

    The target version is read from Microsoft's official .NET release metadata
    (latest-runtime for the 10.0 channel). If that can't be reached, $MinimumVersion is used.

    Run as: SYSTEM | 64-bit PowerShell: Yes | Enforce signature check: No (unless you sign it)
#>

# ---------------- Settings ----------------
$InstallIfMissing = $true          # $false = only patch devices that already have .NET 10
$MinimumVersion   = '10.0.15'      # Fallback floor if release metadata is unreachable - update as needed
# ------------------------------------------

$ErrorActionPreference = 'Stop'
$LogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DotNet10-Runtime.log'
function Write-Log([string]$Msg) {
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    try { Add-Content -Path $LogFile -Value $line } catch {}
    Write-Host $Msg   # Write-Host (not Write-Output) so function return values aren't polluted
}

function Get-TargetVersion {
    $urls = @(
        'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json',
        'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json'
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($u in $urls) {
        try {
            $meta = Invoke-RestMethod -Uri $u -UseBasicParsing -TimeoutSec 30
            if ($meta.'latest-runtime') { return [version]($meta.'latest-runtime' -replace '-.*$','') }
        } catch { }
    }
    Write-Log "Release metadata unreachable - using fallback minimum $MinimumVersion"
    return [version]$MinimumVersion
}

function Get-InstalledDotNet10 {
    $versions = @()
    # Primary: shared framework folder
    $fx = Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.NETCore.App'
    if (Test-Path $fx) {
        $versions += Get-ChildItem $fx -Directory |
            Where-Object { $_.Name -match '^10\.\d+\.\d+$' } |
            ForEach-Object { [version]$_.Name }
    }
    # Secondary: installer registry
    $reg = 'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App'
    if (Test-Path $reg) {
        $versions += (Get-Item $reg).Property |
            Where-Object { $_ -match '^10\.\d+\.\d+$' } |
            ForEach-Object { [version]$_ }
    }
    $versions | Sort-Object -Unique
}

try {
    $installed = @(Get-InstalledDotNet10)
    $target    = Get-TargetVersion

    if ($installed.Count -eq 0) {
        if ($InstallIfMissing) {
            Write-Log "NON-COMPLIANT: .NET 10 runtime not installed (target $target)"
            exit 1
        }
        Write-Log "COMPLIANT: .NET 10 runtime not installed and not required"
        exit 0
    }

    $latest = $installed | Sort-Object -Descending | Select-Object -First 1
    $stale  = $installed | Where-Object { $_ -lt $target }

    if ($latest -lt $target) {
        Write-Log "NON-COMPLIANT: installed $($installed -join ', ') - target $target"
        exit 1
    }
    if ($stale) {
        # Latest is present but an old patch folder lingers - Defender will still flag it
        Write-Log "COMPLIANT (warning): $target present, older patch(es) still on disk: $($stale -join ', ')"
        exit 0
    }

    Write-Log "COMPLIANT: .NET runtime $latest installed (target $target)"
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}