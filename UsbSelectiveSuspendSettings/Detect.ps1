[CmdletBinding()]
param()

<#

Function name: New-LogFile

Description:
Creates a new log file for script execution.

#>
function New-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$LogPath,
        [Parameter(Position = 1, Mandatory)]
        [string]$LogName
    )

    #Resolve the path provided by `-LogPath`. Throw a terminating error if it fails to resolve the path.
    $logPathResolved = (Resolve-Path -Path $LogPath -ErrorAction "Stop").Path

    #Test if the path provided by `-LogPath` is not a directory and throw a terminating error if it is.
    if ((Get-Item -Path $logPathResolved).Attributes -ne [System.IO.FileAttributes]::Directory) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new("$'($logPathResolved)'' is not a directory."),
                "LogPathIsNotDir",
                [System.Management.Automation.ErrorCategory]::InvalidType,
                $logPathResolved
            )
        )
    }

    #Get the current date and time and form the name of the log file.
    $currentDateTimeString = [System.DateTime]::Now.ToString("yyyy-MM-dd_HH-mm-ss")
    $logFileName = "$($LogName)_$($currentDateTimeString).log"

    #Create the log file.
    $fullLogFilePath = Join-Path -Path $LogPath -ChildPath $logFileName
    $logFileItem = New-Item -Path $fullLogFilePath -ItemType "File" -ErrorAction "Stop" -WhatIf:$false

    return $logFileItem
}

<#

Function name: New-LogMessage

Description:
Creates a new entry in the log file created by `New-LogFile` and also outputs to the proper console output.

#>
function New-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [System.IO.FileInfo]$LogFile,
        [Parameter(Position = 1)]
        [ValidateSet(
            "Error",
            "Standard",
            "Verbose",
            "Warning"
        )]
        [string]$MessageType = "Standard",
        [Parameter(Position = 2, Mandatory)]
        [string]$Message
    )

    #Get the current date and time.
    $currentDateTimeString = [System.DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss zzzz")

    #Write the log message to the console's stream determined by the `-MessageType` parameter.
    switch ($MessageType) {
        "Error" {
            Write-Error -Message $Message
            break
        }

        "Warning" {
            Write-Warning -Message $Message
            break
        }

        Default {
            Write-Verbose -Message $Message
            break
        }
    }

    #Create the start of the log file's message.
    $logFileMessageStartString = $null
    switch ($MessageType) {
        "Standard" {
            #If `-MessageType` is set to 'Standard', generate a basic start of the log entry.
            $logFileMessageStartString = "[$($currentDateTimeString)] -"
            break
        }

        Default {
            #If `-MessageType` is set to anything but 'Standard', generate the start of the log entry with the provided log message type.
            $logFileMessageStartString = "[$($currentDateTimeString)] - $($MessageType.ToUpper()) -"
            break
        }
    }

    #Merge the start of the entry with the message provided and append it to the log file.
    $logFileMessageString = "$($logFileMessageStartString) $($Message)"
    $logFileMessageString | Out-File -FilePath $LogFile.FullName -Append
}

<#

Function name: Start-ProcessRedirectedOutput

Description:
A wrapper for the `Start-Process` cmdlet that automatically redirects the standard output of the process to a temporary file and then returns that data as a string.

#>
function Start-ProcessRedirectedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)]
        [string]$FilePath,
        [Parameter(Position = 1)]
        [string[]]$ArgumentList
    )

    #Create a temporary file to redirect the process output to.
    $tmpFile = New-TemporaryFile

    #Create a splat of the parameters we're going to pass to the `Start-Process` cmdlet.
    $startProcSplat = @{
        "FilePath"               = $FilePath;
        "NoNewWindow"            = $true;
        "Wait"                   = $true;
        "RedirectStandardOutput" = $tmpFile.FullName;
    }

    #If `-ArgumentList` is not null, then add the value to the splat.
    if ($null -ne $ArgumentList) {
        $startProcSplat.Add("ArgumentList", $ArgumentList)
    }

    #Start the process.
    $null = Start-Process @startProcSplat

    #Get the contents of the output from the temp file and remove the temp file.
    $standardOutputContents = Get-Content -Path $tmpFile.FullName -Raw
    Remove-Item -Path $tmpFile.FullName -Force

    #Return the output data.
    return $standardOutputContents
}

<#

Class name: PowerSettingConfig

Description:
Custom class defined for parsing `powercfg.exe` output related to a power setting query.
#>
class PowerSettingConfig {
    [string]$DisplayName
    [string]$SettingGuid
    [int]$CurrentACSetting
    [int]$CurrentDCSetting

    PowerSettingConfig([string]$powerCfgOutput, [string]$powerSettingGuid) {
        #Parse the string from the `powercfg.exe` output.
        $powerCfgSettingCommandRegex = [System.Text.RegularExpressions.Regex]::new("Power Setting GUID:\s(?'powerSettingGuid'$($powerSettingGuid))\s+\((?'powerSetting'.+)\)(?:\r|\n).+Current AC Power Setting Index: (?'acSettingVal'[a-z0-9]+)(?:\r|\n).+Current DC Power Setting Index: (?'dcSettingVal'[a-z0-9]+)", @([System.Text.RegularExpressions.RegexOptions]::Singleline))
        $powerCfgSettingsMatch = $powerCfgSettingCommandRegex.Match($powerCfgOutput)

        #Set the class properties to the data parsed from the `powercfg.exe` output.
        $this.DisplayName = $powerCfgSettingsMatch.Groups['powerSetting'].Value
        $this.SettingGuid = $powerCfgSettingsMatch.Groups['powerSettingGuid'].Value
        $this.CurrentACSetting = [int]($powerCfgSettingsMatch.Groups['acSettingVal'].Value)
        $this.CurrentDCSetting = [int]($powerCfgSettingsMatch.Groups['dcSettingVal'].Value)
    }
}

#Create a new log file.
$logFile = New-LogFile -LogPath ([System.IO.Path]::GetTempPath()) -LogName "Remediate-USBSelectiveSuspend-Settings"
$logMessageSplat = @{
    "LogFile" = $logFile;
}

Write-Warning "Log will be located at: $($logFile.FullName)"
New-LogMessage @logMessageSplat -Message "Starting script execution."
New-LogMessage @logMessageSplat -Message "Testing if the USB Selective Suspend setting is enabled."

#Define the USB setting group and the 'USB selective suspend' setting GUIDs.
$powerUsbSettingSubGroupGuid = "2a737441-1930-4402-8d77-b2bebba308a3"
$powerUsbSelectiveSuspendSettingGuid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

#Parse the output of `powercfg.exe /GetActiveScheme` to get the currently active power scheme.
$activeSchemeRegex = [System.Text.RegularExpressions.Regex]::new("^Power Scheme GUID:\s(?'powerSchemeGuid'[a-z0-9-]*)\s+\(.+\)$")
$powercfgActiveSchemeOut = Start-ProcessRedirectedOutput -FilePath "powercfg.exe" -ArgumentList @("/GetActiveScheme")
$currentlyActiveScheme = $activeSchemeRegex.Match($powercfgActiveSchemeOut).Groups['powerSchemeGuid'].Value

New-LogMessage @logMessageSplat -Message "Currently active power scheme:`n$($powercfgActiveSchemeOut)"

#Get the currently active scheme's settings for the USB settings group and transform it into the `PowerSettingConfig` class.
$powerCfgQueryOutput = Start-ProcessRedirectedOutput -FilePath "powercfg.exe" -ArgumentList @("/Query", $currentlyActiveScheme, $powerUsbSettingSubGroupGuid)
$currentUsbSelectiveSuspendSettings = [PowerSettingConfig]::new($powerCfgQueryOutput, $powerUsbSelectiveSuspendSettingGuid)

New-LogMessage @logMessageSplat -Message "Current settings:`n$($powerCfgQueryOutput)"

if (($currentUsbSelectiveSuspendSettings.CurrentACSetting -eq 1) -or ($currentUsbSelectiveSuspendSettings.CurrentDCSetting -eq 1)) {
    #If the current AC or DC settings are set to `1`, then the desired settings are not set. Return a failure, with `exit 1`, so Intune can run the remediation script.
    New-LogMessage @logMessageSplat -Message "Settings are not in a desired state." -MessageType Warning
    New-LogMessage @logMessageSplat -Message "Script execution completed."
    exit 1
}
else {
    #If the current AC and DC settings are set to `0`, then the desired settings are correct. Return a success, with `exit 0`, so Intune knows not to remediate.
    New-LogMessage @logMessageSplat -Message "Settings are in a desired state."
    New-LogMessage @logMessageSplat -Message "Script execution completed."
    exit 0
}