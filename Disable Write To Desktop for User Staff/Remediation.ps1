$DesktopPath = "C:\Users\Staff\Desktop"
$User = "Staff"

if (Test-Path $DesktopPath) {
    try {
        $Acl = Get-Acl $DesktopPath
        
        # Define the Deny rule
        $Ar = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $User,
            "Write, AppendData",
            "Deny"
        )
        
        $Acl.AddAccessRule($Ar)
        Set-Acl $DesktopPath $Acl
        Write-Host "Successfully applied Deny Write rule to Staff Desktop."
        exit 0
    } catch {
        Write-Error "Failed to set ACL: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-Warning "Target path $DesktopPath not found."
    exit 1
}