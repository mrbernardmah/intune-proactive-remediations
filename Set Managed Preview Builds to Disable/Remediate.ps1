<#
.SYNOPSIS
    Intune Remediation - REMEDIATION
    Sets ManagePreviewBuilds in both:
      - MDM PolicyManager store: HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update
      - GPO policy key:          HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

    Values:
      0 = Disable preview builds
      1 = Disable preview builds once the next release is public
      2 = Enable preview builds
#>

$DesiredValue = 0   # <-- must match detection script

$MdmPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
$GpoPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

function Set-RegDword($Path, $Name, $Value) {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Get-RegValue($Path, $Name) {
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

try {
    # MDM PolicyManager store
    Set-RegDword $MdmPath 'ManagePreviewBuilds' $DesiredValue

    # GPO policy key (1 = policy enabled, PolicyValue = selected option)
    Set-RegDword $GpoPath 'ManagePreviewBuilds'            1
    Set-RegDword $GpoPath 'ManagePreviewBuildsPolicyValue' $DesiredValue

    # Verify
    $mdmValue   = Get-RegValue $MdmPath 'ManagePreviewBuilds'
    $gpoEnabled = Get-RegValue $GpoPath 'ManagePreviewBuilds'
    $gpoValue   = Get-RegValue $GpoPath 'ManagePreviewBuildsPolicyValue'

    if ($mdmValue -eq $DesiredValue -and $gpoEnabled -eq 1 -and $gpoValue -eq $DesiredValue) {
        Write-Output "Remediated: MDM=$mdmValue, GPO enabled=$gpoEnabled, GPO value=$gpoValue"
        exit 0
    }

    Write-Output "Remediation verify failed: MDM=$mdmValue, GPO enabled=$gpoEnabled, GPO value=$gpoValue"
    exit 1
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}