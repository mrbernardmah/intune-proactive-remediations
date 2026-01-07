$oldThumbprint = "XYZ"
$newThumbprint = "ABC"
$oldCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $oldThumbprint }
$newCert = Get-ChildItem -Path Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq $newThumbprint }
if ($oldCert -and $newCert) {
    Write-Output "Old certificate exists and new certificate is present. Remediation required."
    exit 1
} else {
    Write-Output "No remediation needed. Either old certificate is missing or new certificate is not in place."
    exit 0
}
