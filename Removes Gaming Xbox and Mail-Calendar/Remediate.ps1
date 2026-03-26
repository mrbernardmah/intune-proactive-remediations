# Remediate Script
$ErrorActionPreference = 'SilentlyContinue'
$AppCount = 0
# List with Apps to remove
$AppsToRemove = @(
    "microsoft.windowscommunicationsapps", 
    "Microsoft.XboxGamingOverlay"
)

$AppsInstalled=Get-AppxPackage -AllUsers | Select-Object -ExpandProperty Name
$ProvAppsInstalled=Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName
ForEach ($AppRemove in $AppsToRemove) {
    If (($AppRemove -in $AppsInstalled)) {
        Try {
            #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Trying to remove the package: $($AppRemove)."
            $AppRemovePackages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $AppRemove }
            $RemNum = $AppRemovePackages.Count
            $nMax = $RemNum-1
            If ($RemNum -ge 2) {
                #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Found $($RemNum) versions of $($AppRemove)."
                For ($n=0; $n -eq $nMax; $n++) {
                    $AppCount++
                    Remove-AppxPackage -Package $AppRemovePackages.PackageFullName[$n] -AllUsers
                    #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Successfully removed: $($AppRemovePackages.PackageFullName[$n])."
                }
            }
            Else {
                $AppCount++
                Remove-AppxPackage -Package $AppRemovePackages.PackageFullName -AllUsers
                #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Successfully removed: $($AppRemovePackages.PackageFullName)."
            }
        }
        Catch {
            #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "There was an error when attempting to remove $($AppRemove)."
        }
    }
    If (($AppRemove -in $ProvAppsInstalled)) {
        $AppCount++
        Try {
            #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Trying to remove the provisioned package: $($AppRemove)."
            $AppRemoveProvPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $AppRemove }
            Remove-AppxProvisionedPackage -Online -PackageName $AppRemoveProvPackage.PackageName -AllUsers
            #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Successfully removed: $($AppRemoveProvPackage.PackageName)."
        }
        Catch {
            #Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "There was an error when attempting to remove $($AppRemoveProvPackage.PackageName)."
        }
    }
}
#Write-EventLog -LogName Application -Source "Microsoft Intune Management Extension" -EventID 9999 -Message "Removed a total of $AppCount packages."