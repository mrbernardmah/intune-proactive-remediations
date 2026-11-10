<#
.SYNOPSIS
    Intune Remediations - DETECTION script.
    Flags devices whose Microsoft Defender Antivirus signatures are older than $MaxAgeHours.

.NOTES
    Run as SYSTEM, 64-bit PowerShell.
    Exit 0 = compliant (signatures current)
    Exit 1 = non-compliant (remediation runs)
#>

$MaxAgeHours = 24

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
}
catch {
    Write-Output "Defender status unavailable: $($_.Exception.Message)"
    exit 1
}

# Defender not the active AV (e.g. passive mode or third-party AV) - signatures are not our problem here
if ($status.AMRunningMode -and $status.AMRunningMode -notin @('Normal', 'EDR Block Mode')) {
    Write-Output "Defender running mode is '$($status.AMRunningMode)'. Skipping. RTP: $($status.RealTimeProtectionEnabled)"
    exit 0
}

$lastUpdated = $status.AntivirusSignatureLastUpdated
$ageHours    = [math]::Round((New-TimeSpan -Start $lastUpdated -End (Get-Date)).TotalHours, 1)
$version     = $status.AntivirusSignatureVersion

if ($ageHours -gt $MaxAgeHours) {
    Write-Output "STALE: signatures $version last updated $lastUpdated ($ageHours h old)"
    exit 1
}

Write-Output "OK: signatures $version last updated $lastUpdated ($ageHours h old)"
exit 0
