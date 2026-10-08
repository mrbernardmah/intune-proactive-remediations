<#
.SYNOPSIS
    Intune Proactive Remediation - REMEDIATION (Python + required pip packages)
.NOTES
    Run as: SYSTEM (Run this script using the logged-on credentials = No)
    64-bit PowerShell: Yes
#>

$RequiredPackages = @(
    "azure-identity",
    "azure-mgmt-resource",
    "msal",
    "msgraph-sdk",
    "python-dotenv",
    "pandas",
    "openpyxl",
    "requests"
)

$PythonVersion = "3.12.2"
$LogDir  = "$env:ProgramData\IntuneRemediation"
$LogFile = Join-Path $LogDir "PythonEnvironment.log"
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

function Write-Log([string]$Message, [string]$Level = "INFO") {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $line
    Write-Output $line
}

function Get-PythonExecutable {
    $possiblePaths = @(
        "$env:ProgramFiles\Python312\python.exe",
        "${env:ProgramFiles(x86)}\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { return $path }
    }
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*WindowsApps*") {
        return $cmd.Source
    }
    return $null
}

function Normalize-PackageName([string]$Name) {
    return ($Name.ToLower() -replace '[-_.]+', '-')
}

# --- STEP 1: Install Python if missing ---
$pythonCmd = Get-PythonExecutable

if (-not $pythonCmd) {
    Write-Log "Python not found. Starting silent installation of $PythonVersion..."
    $installerUrl  = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
    $installerPath = Join-Path $env:TEMP "python-installer.exe"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

        $installArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1"
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru

        if ($process.ExitCode -ne 0) {
            Write-Log "Python installer failed with exit code $($process.ExitCode)" "ERROR"
            exit 1
        }

        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        Write-Log "Python installed successfully."
    }
    catch {
        Write-Log "Failed to download or install Python: $_" "ERROR"
        exit 1
    }

    $pythonCmd = Get-PythonExecutable
    if (-not $pythonCmd) {
        Write-Log "Python installed but executable could not be resolved." "ERROR"
        exit 1
    }
}

Write-Log "Using Python interpreter at: $pythonCmd"

# --- STEP 2: Install missing pip packages ---
try {
    $installedList = & $pythonCmd -m pip list --format=freeze 2>$null
    if ($LASTEXITCODE -ne 0) { throw "pip list returned exit code $LASTEXITCODE" }
    $installed = $installedList | ForEach-Object { Normalize-PackageName (($_ -split '==')[0]) }
}
catch {
    Write-Log "pip execution failed: $_" "ERROR"
    exit 1
}

$missing = @($RequiredPackages | Where-Object { $installed -notcontains (Normalize-PackageName $_) })

if ($missing.Count -gt 0) {
    Write-Log "Installing missing packages: $($missing -join ', ')"

    & $pythonCmd -m pip install --upgrade pip --quiet 2>&1 | Out-Null

    & $pythonCmd -m pip install @missing --quiet 2>&1 | ForEach-Object { Add-Content -Path $LogFile -Value $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "pip install failed with exit code $LASTEXITCODE" "ERROR"
        exit 1
    }
    Write-Log "Successfully installed missing packages."
}
else {
    Write-Log "All required packages already present."
}

exit 0
