<#
.SYNOPSIS
    Intune Remediations - DETECTION script: find bundled OpenSSL DLLs and flag end-of-support / unpatched copies.

.DESCRIPTION
    Scans Program Files, Program Files (x86), ProgramData and every user profile's AppData for
    libcrypto*/libssl*/libeay32/ssleay32 DLLs, works out the real OpenSSL version (from the DLL's
    embedded "OpenSSL x.y.z" string, falling back to the file version resource / filename), and
    maps each copy to its parent app folder.

    Exit 1 = at least one copy is end-of-support or below the minimum patch for its branch
    Exit 0 = nothing found, or all copies are on a supported, patched branch

    Output: one summary line (shown in the Intune "Pre-remediation detection output" column).
    Full detail: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OpenSSL-Inventory.csv / .log
    (picked up by Intune "Collect diagnostics").

    Run as: SYSTEM | 64-bit PowerShell: Yes | No remediation script needed (detect-only / reporting)
#>

# ---------------- Settings: review after each OpenSSL security release ----------------
# Supported branches and minimum patched release. Source: openssl-library.org release strategy / downloads.
#   3.5 LTS -> Apr 2030 | 4.0 -> May 2027 | 4.1 -> Nov 2027
#   EOS: 1.0.2, 1.1.1, 3.0 (Sep 2026), 3.1-3.3, 3.4 (22 Oct 2026), 3.6 (1 Nov 2026)
$MinimumPatch = @{
    '3.5' = '3.5.9'
    '4.0' = '4.0.3'
    '4.1' = '4.1.0'
}
$MaxFileSizeMB = 25   # skip version-string scan on anything larger
# ---------------------------------------------------------------------------------------

$ErrorActionPreference = 'SilentlyContinue'
$LogDir  = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$CsvPath = Join-Path $LogDir 'OpenSSL-Inventory.csv'
$LogPath = Join-Path $LogDir 'OpenSSL-Inventory.log'
$NamePattern = '^(libcrypto|libssl)[-_0-9a-z]*\.dll$|^(libeay32|ssleay32)\.dll$'

function Get-OpenSSLVersion([IO.FileInfo]$File) {
    # 1) Embedded version string - most reliable, apps often stamp their own FileVersion on the DLL
    if ($File.Length -le ($MaxFileSizeMB * 1MB)) {
        try {
            $text = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($File.FullName))
            $m = [regex]::Match($text, 'OpenSSL (\d+\.\d+\.\d+[a-z]{0,2})[ \-]')
            if ($m.Success) { return @{ Version = $m.Groups[1].Value; Source = 'embedded' } }
        } catch { }
    }
    # 2) Version resource
    foreach ($v in $File.VersionInfo.ProductVersion, $File.VersionInfo.FileVersion) {
        if ($v -match '^(\d+\.\d+\.\d+[a-z]{0,2})') { return @{ Version = $Matches[1]; Source = 'resource' } }
    }
    # 3) Filename (branch only)
    switch -Regex ($File.Name) {
        '-1_1'                 { return @{ Version = '1.1.1?'; Source = 'filename' } }
        '-(\d+)(-x64)?\.dll$'  { return @{ Version = "$($Matches[1]).x"; Source = 'filename' } }
        'eay32|ssleay32'       { return @{ Version = '1.0.x'; Source = 'filename' } }
    }
    return @{ Version = 'unknown'; Source = 'none' }
}

function Get-Status([string]$Version) {
    if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        # 1.x letter releases, branch-only or unknown
        if ($Version -match '^(0|1)\.') { return 'EOS' }
        if ($Version -match '^(\d+\.\d+)' -and $MinimumPatch.ContainsKey($Matches[1])) { return 'Unverified' }
        if ($Version -eq 'unknown') { return 'Unverified' }
        return 'EOS'
    }
    $branch = "$($Matches[1]).$($Matches[2])"
    if (-not $MinimumPatch.ContainsKey($branch)) { return 'EOS' }
    if ([version]$Version -lt [version]$MinimumPatch[$branch]) { return 'Outdated' }
    return 'OK'
}

function Get-ParentApp([string]$Path) {
    $rules = @(
        '^[A-Za-z]:\\Program Files(?: \(x86\))?\\WindowsApps\\(?<app>[^\\_]+)',
        '^[A-Za-z]:\\Program Files(?: \(x86\))?\\(?<app>[^\\]+(?:\\[^\\]+)?)\\',
        '^[A-Za-z]:\\ProgramData\\(?<app>[^\\]+(?:\\[^\\]+)?)\\',
        '^[A-Za-z]:\\Users\\(?<user>[^\\]+)\\AppData\\(?:Local|Roaming)\\(?:Programs\\)?(?<app>[^\\]+)'
    )
    foreach ($r in $rules) {
        $m = [regex]::Match($Path, $r)
        if ($m.Success) {
            if ($m.Groups['user'].Success) { return "$($m.Groups['app'].Value) (user $($m.Groups['user'].Value))" }
            return $m.Groups['app'].Value
        }
    }
    return (Split-Path $Path -Parent)
}

# ---- Build scan roots (SYSTEM's own LOCALAPPDATA is useless - enumerate every profile) ----
$roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) | Where-Object { $_ -and (Test-Path $_) }
Get-ChildItem "$env:SystemDrive\Users" -Directory -Force |
    Where-Object { $_.Name -notin 'Public','Default','Default User','All Users' } |
    ForEach-Object {
        foreach ($sub in 'AppData\Local', 'AppData\Roaming') {
            $p = Join-Path $_.FullName $sub
            if (Test-Path $p) { $roots += $p }
        }
    }

# ---- Scan ----
$files = foreach ($root in ($roots | Select-Object -Unique)) {
    Get-ChildItem -Path $root -Recurse -File -Force -Filter '*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $NamePattern -and $_.FullName -notmatch '\\Microsoft\\IntuneManagementExtension\\' }
}

$results = foreach ($f in $files) {
    $v = Get-OpenSSLVersion $f
    [pscustomobject]@{
        App           = Get-ParentApp $f.FullName
        File          = $f.Name
        OpenSSL       = $v.Version
        VersionSource = $v.Source
        Status        = Get-Status $v.Version
        FileVersion   = $f.VersionInfo.FileVersion
        Path          = $f.FullName
        Modified      = $f.LastWriteTime.ToString('yyyy-MM-dd')
    }
}

# libssl without its own version string inherits from libcrypto in the same folder
foreach ($r in $results | Where-Object { $_.VersionSource -ne 'embedded' }) {
    $sib = $results | Where-Object { $_.VersionSource -eq 'embedded' -and (Split-Path $_.Path) -eq (Split-Path $r.Path) } | Select-Object -First 1
    if ($sib) { $r.OpenSSL = $sib.OpenSSL; $r.VersionSource = 'sibling'; $r.Status = $sib.Status }
}

# ---- Write detail ----
try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $results | Sort-Object Status, App | Export-Csv -Path $CsvPath -NoTypeInformation -Force
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content $LogPath "==== $stamp  $($results.Count) OpenSSL DLL(s) found ===="
    $results | Sort-Object Status, App | ForEach-Object {
        Add-Content $LogPath ("[{0}] {1} | OpenSSL {2} ({3}) | {4}" -f $_.Status, $_.App, $_.OpenSSL, $_.VersionSource, $_.Path)
    }
} catch { }

# ---- Summary line for Intune (max 2048 chars) ----
if (-not $results) {
    Write-Output "OK: no bundled OpenSSL DLLs found"
    exit 0
}

$bad = $results | Where-Object { $_.Status -in 'EOS', 'Outdated' }
$byApp = $results | Group-Object App | ForEach-Object {
    $worst = ($_.Group.Status | Sort-Object { @{EOS=0; Outdated=1; Unverified=2; OK=3}[$_] } | Select-Object -First 1)
    $vers  = ($_.Group.OpenSSL | Sort-Object -Unique) -join '/'
    [pscustomobject]@{ Text = "$($_.Name)=$vers[$worst]"; Rank = @{EOS=0; Outdated=1; Unverified=2; OK=3}[$worst] }
} | Sort-Object Rank

$summary = "{0}: {1} EOS, {2} outdated, {3} total | {4}" -f `
    $(if ($bad) { 'ISSUES' } else { 'OK' }),
    @($results | Where-Object Status -eq 'EOS').Count,
    @($results | Where-Object Status -eq 'Outdated').Count,
    $results.Count,
    (($byApp.Text) -join '; ')
if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 1990) + ' ...(see CSV)' }

Write-Output $summary
if ($bad) { exit 1 } else { exit 0 }