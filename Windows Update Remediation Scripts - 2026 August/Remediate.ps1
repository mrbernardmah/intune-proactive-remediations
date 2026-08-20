#Requires -Version 5.1
<#
.SYNOPSIS
    Windows Update Remediation Tool - Automated remediation and repair utility.
.DESCRIPTION
    Fixes common Windows Update issues by cleaning caches, resetting services,
    running DISM repairs, and executing diagnostics.
.AUTHOR
    Bernard Mah Devicie
#>

# Ensure Administrator Privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This tool must be run as Administrator. Please relaunch PowerShell with 'Run as administrator'."
    exit 1
}

# Global Variables
$script:LogDir  = "C:\ProgramData\Devicie\Logs"
$script:LogFile = "$script:LogDir\WinUpdate_Remediation.log"

if (-not (Test-Path -LiteralPath $script:LogDir)) {
    try { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null } catch {}
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
   
    # Write to Console
    Write-Host $logLine
   
    # Write to Log File
    try { $logLine | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 } catch {}
}

function Invoke-Step1 {
    Write-Log "Step 1/11 - Clearing Windows Update policies..."
    $Path = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
    if (Test-Path $Path) { Remove-Item -Path $Path -Recurse -Verbose -ErrorAction SilentlyContinue; Write-Log "  Deleted: $Path" } else { Write-Log "  Not found: $Path" }
   
    $key = "SOFTWARE\Microsoft\PolicyManager\current\device\Update"
    if (Test-Path $key) {
        $val = Get-Item $key -EA Ignore; $props = $val.Property
        if ($props -contains "PausedQualityDate") { Remove-ItemProperty -Path $key -Name "PausedQualityDate" -Verbose -ErrorAction SilentlyContinue; Write-Log "  Cleared: PausedQualityDate" }
        if ($props -contains "PausedFeatureDate") { Remove-ItemProperty -Path $key -Name "PausedFeatureDate" -Verbose -ErrorAction SilentlyContinue; Write-Log "  Cleared: PausedFeatureDate" }
        if ($props -contains "PausedQualityStatus") { $v = $val.GetValue("PausedQualityStatus"); if ($v -ne "0") { Set-ItemProperty -Path $key -Name "PausedQualityStatus" -Value "0" -Verbose; Write-Log "  Reset: PausedQualityStatus (old: $v)" } else { Write-Log "  Already 0: PausedQualityStatus" } }
        if ($props -contains "PausedFeatureStatus") { $v = $val.GetValue("PausedFeatureStatus"); if ($v -ne "0") { Set-ItemProperty -Path $key -Name "PausedFeatureStatus" -Value "0" -Verbose; Write-Log "  Reset: PausedFeatureStatus (old: $v)" } else { Write-Log "  Already 0: PausedFeatureStatus" } }
    } else { Write-Log "  Not found: $key" }
   
    $key2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update"
    if (Test-Path $key2) {
        $val2 = Get-Item $key2 -EA Ignore; $props2 = $val2.Property
        if ($props2 -contains "PauseQualityUpdatesStartTime") { Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $key2 -Name "PauseQualityUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue; Write-Log "  Cleared: PauseQualityUpdatesStartTime" }
        if ($props2 -contains "PauseFeatureUpdatesStartTime") { Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime" -Verbose -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_ProviderSet" -Verbose -ErrorAction SilentlyContinue; Remove-ItemProperty -Path $key2 -Name "PauseFeatureUpdatesStartTime_WinningProvider" -Verbose -ErrorAction SilentlyContinue; Write-Log "  Cleared: PauseFeatureUpdatesStartTime" }
        if ($props2 -contains "PauseQualityUpdates") { $v = $val2.GetValue("PauseQualityUpdates"); if ($v -ne "0") { Set-ItemProperty -Path $key2 -Name "PauseQualityUpdates" -Value "0" -Verbose; Write-Log "  Reset: PauseQualityUpdates (old: $v)" } else { Write-Log "  Already 0: PauseQualityUpdates" } }
        if ($props2 -contains "PauseFeatureUpdates") { $v = $val2.GetValue("PauseFeatureUpdates"); if ($v -ne "0") { Set-ItemProperty -Path $key2 -Name "PauseFeatureUpdates" -Value "0" -Verbose; Write-Log "  Reset: PauseFeatureUpdates (old: $v)" } else { Write-Log "  Already 0: PauseFeatureUpdates" } }
        if ($props2 -contains "DeferFeatureUpdatesPeriodInDays") { $v = $val2.GetValue("DeferFeatureUpdatesPeriodInDays"); if ($v -ne "0") { Set-ItemProperty -Path $key2 -Name "DeferFeatureUpdatesPeriodInDays" -Value "0" -Verbose; Write-Log "  Reset: DeferFeatureUpdatesPeriodInDays (old: $v)" } else { Write-Log "  Already 0: DeferFeatureUpdatesPeriodInDays" } }
    } else { Write-Log "  Not found: $key2" }
   
    $key3 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (Test-Path $key3) {
        $val3 = Get-Item $key3 -EA Ignore; $props3 = $val3.Property
        if ($props3 -contains "AllowDeviceNameInTelemetry") { $v = $val3.GetValue("AllowDeviceNameInTelemetry"); if ($v -ne "1") { Set-ItemProperty -Path $key3 -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose; Write-Log "  Fixed: AllowDeviceNameInTelemetry -> 1 (old: $v)" } else { Write-Log "  Already 1: AllowDeviceNameInTelemetry" } } else { New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowDeviceNameInTelemetry" -Value "1" -Verbose; Write-Log "  Created: AllowDeviceNameInTelemetry = 1" }
        if ($props3 -contains "AllowTelemetry_PolicyManager") { $v = $val3.GetValue("AllowTelemetry_PolicyManager"); if ($v -ne "1") { Set-ItemProperty -Path $key3 -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose; Write-Log "  Fixed: AllowTelemetry_PolicyManager -> 1 (old: $v)" } else { Write-Log "  Already 1: AllowTelemetry_PolicyManager" } } else { New-ItemProperty -Path $key3 -PropertyType DWORD -Name "AllowTelemetry_PolicyManager" -Value "1" -Verbose; Write-Log "  Created: AllowTelemetry_PolicyManager = 1" }
    } else { Write-Log "  Not found: $key3" }
   
    $key4 = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser\GWX"
    if (Test-Path $key4) { $val4 = Get-Item $key4 -EA Ignore; if ($val4.Property -contains "GStatus") { $v = $val4.GetValue("GStatus"); if ($v -ne "2") { Set-ItemProperty -Path $key4 -Name "GStatus" -Value "2" -Verbose; Write-Log "  Fixed: GStatus -> 2 (old: $v)" } else { Write-Log "  Already 2: GStatus" } } else { New-ItemProperty -Path $key4 -PropertyType DWORD -Name "GStatus" -Value "2" -Verbose; Write-Log "  Created: GStatus = 2" } } else { Write-Log "  Not found: $key4" }
   
    Write-Log "Step 1/11 - Completed"
}

function Invoke-Step2 {
    Write-Log "Step 2/11 - Stopping Windows Update services..."
    Stop-Service -Name BITS -Force -Verbose -ErrorAction SilentlyContinue
    Stop-Service -Name wuauserv -Force -Verbose -ErrorAction SilentlyContinue
    Stop-Service -Name cryptsvc -Force -Verbose -ErrorAction SilentlyContinue
    Write-Log "Step 2/11 - Completed (BITS, wuauserv, cryptsvc stopped)"
}

function Invoke-Step3 {
    Write-Log "Step 3/11 - Clearing QMGR data files..."
    Remove-Item -Path "$env:allusersprofile\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue -Verbose
    Write-Log "Step 3/11 - Completed"
}

function Invoke-Step4 {
    Write-Log "Step 4/11 - Clearing update cache..."
    Remove-Item -Path "$env:systemroot\SoftwareDistribution" -ErrorAction SilentlyContinue -Recurse -Verbose
    Remove-Item -Path "$env:systemroot\System32\Catroot2" -ErrorAction SilentlyContinue -Recurse -Verbose
    Write-Log "Step 4/11 - Completed (SoftwareDistribution, Catroot2 deleted)"
}

function Invoke-Step5 {
    Write-Log "Step 5/11 - Resetting service permissions..."
    Start-Process "sc.exe" -ArgumentList "sdset bits D:(A;CI;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)" -Wait
    Start-Process "sc.exe" -ArgumentList "sdset wuauserv D:(A;;CCLCSWRPLORC;;;AU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)" -Wait
    Write-Log "Step 5/11 - Completed"
}

function Invoke-Step6 {
    Write-Log "Step 6/11 - Re-registering DLLs..."
    Set-Location $env:systemroot\system32
    $dlls = @("atl.dll","urlmon.dll","mshtml.dll","shdocvw.dll","browseui.dll","jscript.dll","vbscript.dll","scrrun.dll","msxml.dll","msxml3.dll","msxml6.dll","actxprxy.dll","softpub.dll","wintrust.dll","dssenh.dll","rsaenh.dll","gpkcsp.dll","sccbase.dll","slbcsp.dll","cryptdlg.dll","oleaut32.dll","ole32.dll","shell32.dll","initpki.dll","wuapi.dll","wuaueng.dll","wuaueng1.dll","wucltui.dll","wups.dll","wups2.dll","wuweb.dll","qmgr.dll","qmgrprxy.dll","wucltux.dll","muweb.dll","wuwebv.dll")
    $dllCount = 0
    foreach ($dll in $dlls) {
        regsvr32.exe $dll /s; $dllCount++
        if ($dllCount % 10 -eq 0) { Write-Log "  $dllCount/36 DLLs registered..." }
    }
    Write-Log "Step 6/11 - Completed ($dllCount DLLs registered)"
}

function Invoke-Step7 {
    Write-Log "Step 7/11 - Running DISM health checks and component cleanup (This may take several minutes)..."
    try {
        Write-Log "  Scanning image health..."
        Repair-WindowsImage -Online -ScanHealth -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "  Checking image health..."
        Repair-WindowsImage -Online -CheckHealth -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "  Restoring image health..."
        Repair-WindowsImage -Online -RestoreHealth -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "  Executing component cleanup..."
        dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet
    } catch {
        Write-Log "  Error during DISM execution: $($_.Exception.Message)"
    }
    Write-Log "Step 7/11 - Completed"
}

function Invoke-Step8 {
    Write-Log "Step 8/11 - Starting Windows Update services..."
    Start-Service -Name BITS -Verbose -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -Verbose -ErrorAction SilentlyContinue
    Start-Service -Name cryptsvc -Verbose -ErrorAction SilentlyContinue
    Write-Log "Step 8/11 - Completed"
}

function Invoke-Step9 {
    Write-Log "Step 9/11 - Starting update scan (USOClient)..."
    USOClient.exe StartInteractiveScan
    Write-Log "Step 9/11 - Scan started, waiting 5 minutes..."
    Start-Sleep -Seconds 300
    Write-Log "Step 9/11 - Wait completed"
}

function Invoke-Step10 {
    Write-Log "Step 10/11 - Creating diagnostic log with SetupDiag..."
    try {
        $setupDiagUrl = "https://go.microsoft.com/fwlink/?linkid=870142"
        $setupDiagPath = "$script:LogDir\SetupDiag.exe"
        $diagOutput = "$script:LogDir\#Windows Updates - Diagnostics.log"
        $webClient = New-Object System.Net.WebClient
        Write-Log "  Downloading SetupDiag..."
        $webClient.DownloadFile($setupDiagUrl, $setupDiagPath)
        Write-Log "  Download completed"
        
        $checkLogs = Test-Path -Path "$script:LogDir\logs*.zip"
        if ($checkLogs) { Remove-Item -Path "$script:LogDir\logs*.zip" -Force -Recurse; Write-Log "  Old log zips cleaned" }
        
        Write-Log "  Running SetupDiag..."
        & "$setupDiagPath" /Output:"$diagOutput"
        Write-Log "  Diagnostic log created: $diagOutput"
    } catch {
        Write-Log "  SetupDiag failed: $($_.Exception.Message)"
    }
    Write-Log "Step 10/11 - Completed"
}

function Invoke-Step11 {
    Write-Log "Step 11/11 - Checking update status (Pre vs Post scan event log)..."
    try {
        # Pre Check for Update status
        $CheckForUpdatePre = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'
        } -ErrorAction SilentlyContinue
        $TopPre = $CheckForUpdatePre | Select-Object -First 1

        # Trigger Check for Windows update
        Start-Process -FilePath "C:\Windows\System32\USOClient.exe" -ArgumentList "StartInteractiveScan" -WindowStyle Hidden
        Start-Sleep -Seconds 120

        # Post Check for Update status
        $CheckForUpdatePost = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'
        } -ErrorAction SilentlyContinue
        $TopPost = $CheckForUpdatePost | Select-Object -First 1

        Write-Log "PreCFU:-$($TopPre.TimeCreated) ; PostCFU:-$($TopPost.TimeCreated)"
    } catch {
        Write-Log "  Failed to query Windows Update event logs: $($_.Exception.Message)"
    }
    Write-Log "Step 11/11 - Completed"
}

# Execute All Remediation Steps Sequentially
$startTime = Get-Date
Write-Log "=========================================="
Write-Log "Starting Windows Update Remediation Tool"
Write-Log "Log file location: $script:LogFile"
Write-Log "=========================================="

Invoke-Step1
Invoke-Step2
Invoke-Step3
Invoke-Step4
Invoke-Step5
Invoke-Step6
Invoke-Step7
Invoke-Step8
Invoke-Step9
Invoke-Step10
Invoke-Step11

$duration = (Get-Date) - $startTime
Write-Log "=========================================="
Write-Log "Process completed in $($duration.Minutes)m $($duration.Seconds)s."
Write-Log "=========================================="