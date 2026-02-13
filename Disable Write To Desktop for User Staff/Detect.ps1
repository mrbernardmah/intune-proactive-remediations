$StaffProfile = "C:\Users\Staff\Desktop"
$User = "Staff"

if (Test-Path $StaffProfile) {
    $Acl = Get-Acl $StaffProfile
    
    # Check if there is a 'Deny' rule for 'Write' or 'AppendData' for the Staff user
    $RuleFound = $Acl.Access | Where-Object {
        $_.IdentityReference -like "*$User" -and 
        $_.AccessControlType -eq "Deny" -and 
        ($_.FileSystemRights -match "Write" -or $_.FileSystemRights -match "AppendData")
    }

    if ($RuleFound) {
        Write-Host "Desktop is already locked for Staff."
        exit 0 # Compliant
    } else {
        Write-Host "Desktop is NOT locked for Staff."
        exit 1 # Non-Compliant - Triggers Remediation
    }
} else {
    # If the profile doesn't exist, we skip (or you can exit 0 if you don't want to error out)
    Write-Host "Staff profile not found. Skipping."
    exit 0 
}