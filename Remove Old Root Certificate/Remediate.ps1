$oldThumbprint = "XYZ"
$newThumbprint = "ABC"
# Check for the presence of the new certificate
$newCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $newThumbprint }
if ($newCert) {
    Write-Output "New root certificate is present. Proceeding with removal of the old certificate."
    $oldCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $oldThumbprint }
    if ($oldCert) {
        try {
            Remove-Item -Path "Cert:\LocalMachine\Root\$oldThumbprint" -Force
            Write-Output "Old certificate removed successfully."
        } catch {
            Write-Error "Failed to remove old certificate: $_"
        }
    } else {
        Write-Output "Old certificate not found. No action needed."
    }
} else {
    Write-Warning "New root certificate not found. Aborting removal of old certificate to avoid trust issues."
}
