# ==============================================================================
# REMEDIATION SCRIPT: Reset Background Permissions and Reset Microsoft Store
# ==============================================================================

$PackageFamilyName = "Microsoft.WindowsStore_8wekyb3d8bbwe"

# 1. Reset Background Component Permissions to 'Power optimized (recommended)'
$ConsentStorePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\backgroundSync\NonPackaged\$PackageFamilyName"
if (Test-Path $ConsentStorePath) {
    New-ItemProperty -Path $ConsentStorePath -Name "Value" -PropertyType String -Value "Allow" -Force | Out-Null
    Write-Host "Restored ConsentStore backgroundSync to 'Allow'."
}

$BackgroundAccessPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$PackageFamilyName"
if (Test-Path $BackgroundAccessPath) {
    Remove-ItemProperty -Path $BackgroundAccessPath -Name "DisabledByUser" -ErrorAction SilentlyContinue | Out-Null
    Remove-ItemProperty -Path $BackgroundAccessPath -Name "Disabled" -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Removed background application blocks."
}

# 2. Terminate Microsoft Store active instances
Stop-Process -Name "WinStore.App" -Force -ErrorAction SilentlyContinue

# 3. Reset the AppX Package Data
Write-Host "Resetting Microsoft Store System Component..."

try {
    # Attempt native modern AppX package reset
    $StorePackage = Get-AppxPackage -Name "Microsoft.WindowsStore" -AllUsers
    if ($StorePackage) {
        Reset-AppxPackage $StorePackage.PackageFullName -ErrorAction Stop
        Write-Host "Success: Store app package has been successfully reset."
    } else {
        throw "Store package not found via Get-AppxPackage."
    }
} 
catch {
    # Fallback method if Reset-AppxPackage fails or isn't available
    Write-Host "Standard AppX reset bypassed or failed. Attempting fallback protocol..." -ForegroundColor Yellow
    & "winstore://reset"
    Start-Sleep -Seconds 2
    Stop-Process -Name "WinStore.App" -Force -ErrorAction SilentlyContinue
    Write-Host "Success: Fallback component reset signal sent."
}