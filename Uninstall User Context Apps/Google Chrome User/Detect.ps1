<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Detects Google Chrome installed in USER context (per-user, %LOCALAPPDATA%).

.NOTES
    Intune settings:
      - Run this script using the logged-on credentials : Yes
      - Enforce script signature check                  : No
      - Run script in 64-bit PowerShell                 : Yes

    Exit 1 = user-context Chrome found  -> remediation runs
    Exit 0 = compliant (nothing found)

    System-wide Chrome (Program Files / HKLM) is NOT detected or touched.
#>

# Leave empty to target ANY user-context Chrome version.
# Or limit to specific versions, e.g. @('109.0.5414.121','111.0.5563.147','126.0.6478.127')
$TargetVersions = @()

$ErrorActionPreference = 'SilentlyContinue'

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome'
$appDir       = Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application'

$versions = @()

# 1. Per-user uninstall registry entry
if (Test-Path $uninstallKey) {
    $v = (Get-ItemProperty -Path $uninstallKey).DisplayVersion
    if ($v) { $versions += $v } else { $versions += 'unknown(registry)' }
}

# 2. Per-user binaries
$chromeExe = Join-Path $appDir 'chrome.exe'
if (Test-Path $chromeExe) {
    $v = (Get-Item $chromeExe).VersionInfo.ProductVersion
    if ($v) { $versions += $v } else { $versions += 'unknown(file)' }
}

# 3. Leftover version folders (e.g. 158.0.8127.88) without chrome.exe at root
if (Test-Path $appDir) {
    Get-ChildItem -Path $appDir -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        ForEach-Object { $versions += $_.Name }
}

$versions = $versions | Sort-Object -Unique

if (-not $versions) {
    Write-Output "Compliant: no user-context Chrome for $env:USERNAME"
    exit 0
}

if ($TargetVersions.Count -gt 0) {
    $matched = $versions | Where-Object { $TargetVersions -contains $_ }
    if (-not $matched) {
        Write-Output "Compliant: user-context Chrome present ($($versions -join ', ')) but not a targeted version"
        exit 0
    }
    $versions = $matched
}

Write-Output "Non-compliant: user-context Chrome found for $env:USERNAME - version(s): $($versions -join ', ')"
exit 1