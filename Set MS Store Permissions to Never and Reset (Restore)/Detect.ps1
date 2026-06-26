# ==============================================================================
# DETECTION SCRIPT: Check Microsoft Store Power Optimization & Reset State
# ==============================================================================

$PackageFamilyName = "Microsoft.WindowsStore_8wekyb3d8bbwe"
$NeedsRemediation = $false

# 1. Check Modern System Component Privacy API Subkey
$ConsentStorePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\backgroundSync\NonPackaged\$PackageFamilyName"
if (Test-Path $ConsentStorePath) {
    $ConsentValue = (Get-ItemProperty -Path $ConsentStorePath -Name "Value" -ErrorAction SilentlyContinue).Value
    if ($ConsentValue -ne "Allow") {
        Write-Host "Non-Compliant: ConsentStore backgroundSync value is not 'Allow'."
        $NeedsRemediation = $true
    }
}

# 2. Check Standard/Legacy AppX Background Management Path
$BackgroundAccessPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$PackageFamilyName"
if (Test-Path $BackgroundAccessPath) {
    $DisabledByUser = (Get-ItemProperty -Path $BackgroundAccessPath -Name "DisabledByUser" -ErrorAction SilentlyContinue).DisabledByUser
    $Disabled = (Get-ItemProperty -Path $BackgroundAccessPath -Name "Disabled" -ErrorAction SilentlyContinue).Disabled

    if ($null -ne $DisabledByUser -or $null -ne $Disabled) {
        Write-Host "Non-Compliant: Explicit background blocks found in BackgroundAccessApplications."
        $NeedsRemediation = $true
    }
}

# Evaluate compliance status
if ($NeedsRemediation) {
    Write-Host "Device is Non-Compliant. Triggering remediation..."
    Exit 1 # Triggers the Remediation Script
} else {
    Write-Host "Compliant: Microsoft Store is already power optimized."
    Exit 0 # No action required
}