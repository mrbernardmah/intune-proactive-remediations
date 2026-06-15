# --- 1. Detect MSI-Based HP Apps (Original Logic) ---
$MSIApps = Get-CimInstance -ClassName Win32_Product | Where-Object {
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
}

# --- 2. Detect UWP/Store HP Apps (New Logic) ---
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

$UWPAppsFound = @()
foreach ($AppNames in $UWPAppNames) {
    # -AllUsers checks provisioned and currently installed store packages
    $Found = Get-AppxPackage -Name $AppNames -AllUsers -ErrorAction SilentlyContinue
    if ($null -ne $Found) {
        $UWPAppsFound += $Found
    }
}

# --- 3. Evaluate Results ---
if (($MSIApps.Count -eq 0) -and ($UWPAppsFound.Count -eq 0)) {
    Exit 0 # Clean system
}
else {
    Exit 1 # Targets found, remediation required
}