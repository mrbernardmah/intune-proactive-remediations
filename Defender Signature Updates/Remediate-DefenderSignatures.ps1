<#
.SYNOPSIS
    Intune Remediations - REMEDIATION script.
    Updates Microsoft Defender Antivirus signatures, falling back through update sources.

.NOTES
    Run as SYSTEM, 64-bit PowerShell.
    Order tried:
      1. Update-MpSignature (device's configured update source / fallback order)
      2. MpCmdRun -SignatureUpdate (configured sources)
      3. MpCmdRun -SignatureUpdate -MMPC (direct from Microsoft Malware Protection Center)
    Exit 0 = signatures updated / current
    Exit 1 = still stale after all attempts
#>

$MaxAgeHours = 24
$log = @()

function Get-SigState {
    $s = Get-MpComputerStatus -ErrorAction Stop
    [pscustomobject]@{
        Version     = $s.AntivirusSignatureVersion
        LastUpdated = $s.AntivirusSignatureLastUpdated
        AgeHours    = [math]::Round((New-TimeSpan -Start $s.AntivirusSignatureLastUpdated -End (Get-Date)).TotalHours, 1)
    }
}

function Test-Current { ((Get-SigState).AgeHours -le $MaxAgeHours) }

# Find the newest MpCmdRun.exe (platform folder first, then Program Files)
function Get-MpCmdRun {
    $platformRoot = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
    $newest = Get-ChildItem -Path $platformRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'MpCmdRun.exe') } |
        Sort-Object { try { [version]($_.Name -split '-')[0] } catch { [version]'0.0' } } -Descending |
        Select-Object -First 1
    if ($newest) { return (Join-Path $newest.FullName 'MpCmdRun.exe') }

    $fallback = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

try {
    $before = Get-SigState
    $log += "Before: $($before.Version) ($($before.AgeHours)h old)"
}
catch {
    Write-Output "Defender status unavailable: $($_.Exception.Message)"
    exit 1
}

# 1. Native cmdlet
try {
    Update-MpSignature -ErrorAction Stop
    $log += 'Update-MpSignature: ran'
}
catch {
    $log += "Update-MpSignature failed: $($_.Exception.Message)"
}

if (-not (Test-Current)) {
    $mpcmd = Get-MpCmdRun
    if ($mpcmd) {
        # 2. MpCmdRun using configured sources
        & $mpcmd -SignatureUpdate | Out-Null
        $log += "MpCmdRun -SignatureUpdate exit $LASTEXITCODE"

        # 3. Force direct download from Microsoft
        if (-not (Test-Current)) {
            & $mpcmd -SignatureUpdate -MMPC | Out-Null
            $log += "MpCmdRun -SignatureUpdate -MMPC exit $LASTEXITCODE"
        }
    }
    else {
        $log += 'MpCmdRun.exe not found'
    }
}

$after = Get-SigState
$log += "After: $($after.Version) ($($after.AgeHours)h old)"

# Intune shows the last line of output, so keep it to one line
Write-Output ($log -join ' | ')

if ($after.AgeHours -le $MaxAgeHours) { exit 0 } else { exit 1 }
