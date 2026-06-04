# Remove Emergency Admin Account Script
# Removes the emergency break-glass admin account

$Username = "EnterLAPSAccount"

try {
    # Check if user exists
    $UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    
    if ($UserExists) {
        Remove-LocalUser -Name $Username -ErrorAction Stop
        Write-Output "[OK] Emergency admin account '$Username' successfully removed"
    } else {
        Write-Output "[INFO] Emergency admin account '$Username' does not exist"
    }
    
    exit 0
} catch {
    Write-Error "[ERROR] Failed to remove emergency admin account: $_"
    exit 1
}
