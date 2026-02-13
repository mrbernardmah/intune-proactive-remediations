$shortcuts = "Google Chrome.lnk", "Microsoft Edge.lnk"

# Function to attempt deletion
function Remove-Shortcut {
    param([string]$folderPath)
    if (Test-Path $folderPath) {
        foreach ($s in $shortcuts) {
            $target = Join-Path $folderPath $s
            if (Test-Path $target) {
                Remove-Item -Path $target -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# 1. Clean Public Desktop
Remove-Shortcut -folderPath "$env:PUBLIC\Desktop"

# 2. Clean All User Profiles
$userFolders = Get-ChildItem "C:\Users" -Exclude "All Users", "Default", "Default User"
foreach ($user in $userFolders) {
    $desktopPath = Join-Path $user.FullName "Desktop"
    Remove-Shortcut -folderPath $desktopPath
}