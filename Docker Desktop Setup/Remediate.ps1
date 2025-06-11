# Intune Remediation Script to Enable Windows Features, Create Group, and Configure Docker Desktop

# Start transcript to log actions
Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\LogsDockerDesktopSetup.txt"
Write-Output "Transcript started."

# Enable Windows Features without reboot
if (Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart) {
    Write-Output "Microsoft-Hyper-V feature enabled successfully."
} else {
    Write-Output "Failed to enable Microsoft-Hyper-V feature."
}

if (Enable-WindowsOptionalFeature -Online -FeatureName Containers -NoRestart) {
    Write-Output "Containers feature enabled successfully."
} else {
    Write-Output "Failed to enable Containers feature."
}

# Create a local group named "docker-users"
if (-Not (Get-LocalGroup -Name "docker-users" -ErrorAction SilentlyContinue)) {
    if (New-LocalGroup -Name "docker-users") {
        Write-Output "Local group 'docker-users' created successfully."
    } else {
        Write-Output "Failed to create local group 'docker-users'."
    }
} else {
    Write-Output "Local group 'docker-users' already exists."
}

# Get the current logged on local user from the explorer.exe process
$currentUser = (Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE Name = 'explorer.exe'").GetOwner().Domain + "\" + (Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE Name = 'explorer.exe'").GetOwner().User
Write-Output "Current logged on user: $currentUser"

# Check if the current logged on user is in the JHG domain
if ($currentUser -like "Domain\*") {
    # Check if the user is already a member of the "docker-users" group
    $isMember = (Get-LocalGroupMember -Group "docker-users" -Member $currentUser -ErrorAction SilentlyContinue) -ne $null

    if ($isMember) {
        Write-Output "User $currentUser is already a member of the 'docker-users' group."
    } else {
        try {
            # Attempt to add the user to the local "docker-users" group
            Add-LocalGroupMember -Group "docker-users" -Member $currentUser -ErrorAction Stop
            Write-Output "User $currentUser added to 'docker-users' group successfully."
        } catch {
            Write-Output "Failed to add user $currentUser to 'docker-users' group."
        }
    }
} else {
    Write-Output "Current user is not in the JHG domain."
}



function Enable-AutomaticService {
    param (
        [Parameter(Position = 0, Mandatory = $true)] [string]$serviceName
    )
    try {
        Get-Service -Name $serviceName
        Set-Service -Name $serviceName -StartupType Automatic
    }
    catch {
        Write-Error "Service does not exist"
    }
  }
  

  Start-Process "C:\Program Files\Docker\Docker\resources\com.docker.admin.exe" -ArgumentList "start-service"

  Enable-AutomaticService "com.docker.service"

# Stop transcript
Stop-Transcript
Write-Output "Transcript stopped."
