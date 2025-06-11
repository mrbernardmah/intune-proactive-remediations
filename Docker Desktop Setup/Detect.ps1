$dockerExe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$remediationTxt = 'C:\ProgramData\Microsoft\IntuneManagementExtension\LogsDockerDesktopSetup.txt'
$dockerService = 'Docker Desktop Service'
$featureHyperV = 'Microsoft-Hyper-V'
$featureContainers = 'Containers'
$dockerUsersGroup = 'docker-users'

# Check if Docker Desktop is installed
if (-not (Test-Path $dockerExe)) {
    Write-Output "Docker Desktop not installed. No remediation needed."
    exit 0
}

# Check if remediation log exists
$remediationRun = Test-Path $remediationTxt

# Check if Docker service is running and set to automatic
$service = Get-Service -Name $dockerService -ErrorAction SilentlyContinue
$serviceRunning = $service.Status -eq 'Running'
$serviceAutomatic = $service.StartType -eq 'Automatic'

# Check if Docker Users group exists
$dockerGroupExists = (Get-LocalGroup -Name $dockerUsersGroup -ErrorAction SilentlyContinue) -ne $null

# Get the current logged on local user from the explorer.exe process
$currentUser = (Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE Name = 'explorer.exe'").GetOwner().Domain + "\" + (Get-WmiObject -Query "SELECT * FROM Win32_Process WHERE Name = 'explorer.exe'").GetOwner().User

# Check if the current user is a member of the Docker Users group
$currentUserIsMember = (Get-LocalGroupMember -Group $dockerUsersGroup -Member $currentUser -ErrorAction SilentlyContinue) -ne $null

# Check if Windows features are enabled
$hyperVEnabled = (Get-WindowsOptionalFeature -FeatureName $featureHyperV -Online).State -eq 'Enabled'
$containersEnabled = (Get-WindowsOptionalFeature -FeatureName $featureContainers -Online).State -eq 'Enabled'

# Determine the remediation status
if ($remediationRun -and $serviceRunning -and $serviceAutomatic -and $hyperVEnabled -and $containersEnabled -and $dockerGroupExists -and $currentUserIsMember) {
    Write-Output "Docker Desktop installed and remediation already run. No further remediation needed."
    exit 0
} elseif (-not $remediationRun -or -not $serviceRunning -or -not $serviceAutomatic -or -not $hyperVEnabled -or -not $containersEnabled -or -not $dockerGroupExists -or -not $currentUserIsMember) {
    Write-Output "Docker Desktop installed but remediation not run. Remediation needed."
    exit 1
}
