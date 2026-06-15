# --- 1. Remediate UWP/Store HP Apps (New Logic) ---
$UWPAppNames = @(
    "AD2F1837.HPPCHardwareDiagnosticsWindows",
    "AD2F1837.HPPowerManager",
    "AD2F1837.HPPrivacySettings",
    "AD2F1837.HPQuickDrop",
    "AD2F1837.HPSupportAssistant",
    "AD2F1837.HPSystemInformation",
    "AD2F1837.HPAIExperienceCenter",
    "AD2F1837.HPDisplayCenter",
    "AD2F1837.myHP"
)

foreach ($Name in $UWPAppNames) {
    # Find package instances across all user profiles
    $Packages = Get-AppxPackage -Name $Name -AllUsers -ErrorAction SilentlyContinue
    foreach ($Package in $Packages) {
        # Uninstall current active app package instance
        Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
    
    # Remove provisioned app package (stops it from reinstalling for new users)
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
        Where-Object {$_.DisplayName -eq $Name} | 
        Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# --- 2. Remediate MSI-Based HP Apps (Original Loop) ---
do {
    $Apps = Get-CimInstance -ClassName Win32_Product | Where-Object {
        ($_.Name -like "HP Wolf*") -or 
        ($_.Name -like "HP Security*") -or 
        ($_.Name -like "HP Connection Optimizer*") -or 
        ($_.Name -like "HP Documentation*") -or 
        ($_.Name -like "HP Security Update Service*") -or 
        ($_.Name -like "HP Sure Run Module*") -or 
        ($_.Name -like "HP Easy Clean*") -or 
        ($_.Name -like "HP Privacy Settings*") -or 
        ($_.Name -like "HP QuickDrop*") -or 
        ($_.Name -like "HP Support Assistant*") -or 
        ($_.Name -like "HP Wolf Security - Console*") -or 
        ($_.Name -like "HP System Information*") -or 
        ($_.Name -like "HP WorkWell*") -or 
        ($_.Name -like "myHP*")
    } | Select-Object Name, IdentifyingNumber | Sort-Object Name -Descending

    foreach ($App in $Apps) {
        $AppID = $App.IdentifyingNumber
        $ArgumentList = '/uninstall ' + $AppID + ' /quiet /norestart'
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $ArgumentList -Wait -PassThru -ErrorAction SilentlyContinue
    }
} while ($null -ne $Apps)