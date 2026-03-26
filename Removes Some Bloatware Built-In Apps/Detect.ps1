# Detect Script
$ErrorActionPreference = 'SilentlyContinue'
$Detect = 0
# List with Apps to remove
$AppsToRemove = @(
    "Microsoft.BingNews", 
    "Microsoft.BingWeather", 
    "Microsoft.GamingApp", 
    "Microsoft.Xbox.TCUI", 
    "Microsoft.XboxGameOverlay", 
    "Microsoft.XboxGamingOverlay", 
    "Microsoft.XboxIdentityProvider", 
    "Microsoft.XboxSpeechToTextOverlay", 
    "Microsoft.YourPhone", 
    "Microsoft.ZuneMusic", 
    "Microsoft.ZuneVideo", 
    "MicrosoftCorporationII.QuickAssist"
)

$AppsInstalled=Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
$ProvAppsInstalled=Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName
Foreach ($AppRemove in $AppsToRemove) {
    If (($AppRemove -in $AppsInstalled)) {
        $Detect++
        #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Package $AppRemove found."
    }
    If (($AppRemove -in $ProvAppsInstalled)) {
        $Detect++
        #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Provisioned Package $AppRemove found."
    }    
}

If ($Detect -eq 0) {
    #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "No packages to remove."
    Exit 0
}
Else {
    #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Found packages to remove."
    Exit 1
}