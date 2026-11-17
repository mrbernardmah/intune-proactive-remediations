<#
.SYNOPSIS
    Intune Remediations - REMEDIATION script for Microsoft .NET Runtime 10 (x64).

.DESCRIPTION
    1. Installs/upgrades Microsoft.DotNet.Runtime.10 with winget (resolved for SYSTEM context).
    2. If winget is missing or fails, falls back to the official runtime installer from
       Microsoft's .NET release metadata, verified against its published SHA512 hash.
    3. Verifies the installed version afterwards.

    Exit 0 = success, Exit 1 = failure.
    Run as: SYSTEM | 64-bit PowerShell: Yes | Enforce signature check: No (unless you sign it)
#>

$ErrorActionPreference = 'Stop'
$PackageId = 'Microsoft.DotNet.Runtime.10'
$LogFile   = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DotNet10-Runtime.log'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Log([string]$Msg) {
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    try { Add-Content -Path $LogFile -Value $line } catch {}
    Write-Host $Msg   # Write-Host (not Write-Output) so function return values aren't polluted
}

function Get-LatestDotNet10 {
    $fx = Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.NETCore.App'
    if (-not (Test-Path $fx)) { return $null }
    Get-ChildItem $fx -Directory |
        Where-Object { $_.Name -match '^10\.\d+\.\d+$' } |
        ForEach-Object { [version]$_.Name } |
        Sort-Object -Descending | Select-Object -First 1
}

function Get-ReleaseMetadata {
    foreach ($u in 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json',
                   'https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json') {
        try { return Invoke-RestMethod -Uri $u -UseBasicParsing -TimeoutSec 30 } catch { }
    }
    return $null
}

function Get-WingetPath {
    # SYSTEM has no user-scoped winget alias - resolve the App Installer package folder directly
    $resolved = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
    if ($resolved) {
        return ($resolved | Sort-Object { [version](($_.Path -split '_')[1]) } -Descending | Select-Object -First 1).Path
    }
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Winget([string]$Winget, [string]$Verb) {
    $wgArgs = @($Verb, '--id', $PackageId, '--exact', '--source', 'winget', '--scope', 'machine',
              '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Write-Log "Running: winget $($wgArgs -join ' ')"
    $out = & $Winget @wgArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Log ("winget {0} exit code {1} (0x{2:X8})" -f $Verb, $code, $code)
    ($out -split "`r?`n" | Where-Object { $_ -match '\w' } | Select-Object -Last 5) | ForEach-Object { Write-Log "  $_" }
    return $code
}

function Install-FromMicrosoft($Meta) {
    $rel  = $Meta.releases | Where-Object { $_.'release-version' -eq $Meta.'latest-release' } | Select-Object -First 1
    if (-not $rel) { $rel = $Meta.releases | Select-Object -First 1 }
    $file = $rel.runtime.files | Where-Object { $_.rid -eq 'win-x64' -and $_.name -like '*.exe' } | Select-Object -First 1
    if (-not $file) { throw "No win-x64 runtime installer found in release metadata" }

    $dest = Join-Path $env:TEMP "dotnet-runtime-$($rel.runtime.version)-win-x64.exe"
    Write-Log "Fallback: downloading $($file.url)"
    Invoke-WebRequest -Uri $file.url -OutFile $dest -UseBasicParsing -TimeoutSec 600

    $hash = (Get-FileHash -Path $dest -Algorithm SHA512).Hash
    if ($hash -ne $file.hash.ToUpper()) {
        Remove-Item $dest -Force -ErrorAction SilentlyContinue
        throw "SHA512 mismatch on downloaded installer - aborting"
    }
    Write-Log "Hash verified. Installing $($rel.runtime.version) silently"
    $p = Start-Process -FilePath $dest -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
    Remove-Item $dest -Force -ErrorAction SilentlyContinue
    Write-Log "Installer exit code $($p.ExitCode)"
    if ($p.ExitCode -notin 0, 3010, 1641) { throw "Installer failed with exit code $($p.ExitCode)" }
}

try {
    $before = Get-LatestDotNet10
    $meta   = Get-ReleaseMetadata
    $target = if ($meta) { [version]($meta.'latest-runtime' -replace '-.*$','') } else { $null }
    Write-Log "Installed: $(if ($before) { $before } else { 'none' }) | Target: $(if ($target) { $target } else { 'unknown (metadata unreachable)' })"

    # 1) winget
    $winget = Get-WingetPath
    if ($winget) {
        Write-Log "winget found: $winget"
        $verb = if ($before) { 'upgrade' } else { 'install' }
        [void](Invoke-Winget $winget $verb)

        # If upgrade didn't land (e.g. existing runtime not matched to the winget package), try install
        $now = Get-LatestDotNet10
        if ($verb -eq 'upgrade' -and (-not $now -or ($target -and $now -lt $target))) {
            [void](Invoke-Winget $winget 'install')
        }
    } else {
        Write-Log "winget not available in SYSTEM context"
    }

    # 2) Fallback to Microsoft's installer if still not at target
    $now = Get-LatestDotNet10
    if (-not $now -or ($target -and $now -lt $target)) {
        if (-not $meta) { throw "winget did not reach the target and release metadata is unreachable" }
        Install-FromMicrosoft $meta
    }

    # 3) Verify
    $after = Get-LatestDotNet10
    if (-not $after -or ($target -and $after -lt $target)) {
        throw "Verification failed - installed: $after, target: $target"
    }
    Write-Log "SUCCESS: .NET runtime $after installed"
    exit 0
}
catch {
    Write-Log "FAILED: $($_.Exception.Message)"
    exit 1
}