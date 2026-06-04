# Detection Script for Emergency Admin Account Removal
# Returns exit code 0 if account does NOT exist (already removed)
# Returns exit code 1 if account exists (needs to be removed)

$Username = "EnterLAPSAccount"

# Check if user exists
$UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if ($UserExists) {
    Write-Output "[WARNING] Emergency admin account '$Username' exists. Needs remidiation."
    exit 1
} else {
    Write-Output "[OK] Emergency admin account '$Username' does not exist"
    exit 0
}
