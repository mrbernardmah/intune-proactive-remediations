# =======================================================================================
# REMEDIATION SCRIPT: Microsoft Store Restrictions & Reset
# =======================================================================================

$PackageFamilyName = "Microsoft.WindowsStore_8wekyb3d8bbwe"
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$PackageFamilyName"

try {
    # 1. Set Background Component Permissions to 'Never'
    if (-not (Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }
    # 'DisabledByUser' (Value: 2) corresponds to setting the permission to "Never"
    New-ItemProperty -Path $RegistryPath -Name "DisabledByUser" -PropertyType DWord -Value 2 -Force | Out-Null
    Write-Host "Successfully set background permission to 'Never'."

    # 2. Terminate Microsoft Store
    Write-Host "Terminating active Microsoft Store processes..."
    Stop-Process -Name "WinStore.App" -Force -ErrorAction SilentlyContinue

    # 3. Click Reset
    Write-Host "Resetting Microsoft Store application data..." -ForegroundColor Cyan
    $StorePackage = Get-AppxPackage -Name "Microsoft.WindowsStore"
    
    if ($StorePackage) {
        $StorePackage | Reset-AppxPackage
        Write-Host "Operations completed successfully!" -ForegroundColor Green
        Exit 0
    } else {
        Write-Error "Microsoft Store package not found for the current user."
        Exit 1
    }

} catch {
    Write-Error "Remediation failed: $_"
    Exit 1
}