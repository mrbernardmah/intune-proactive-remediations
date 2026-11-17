<#
.SYNOPSIS
    Intune Remediation - DETECTION
    Checks ManagePreviewBuilds in both:
      - MDM PolicyManager store: HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update
      - GPO policy key:          HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate

    Exit 0 = compliant, Exit 1 = needs remediation.

    Values:
      0 = Disable preview builds
      1 = Disable preview builds once the next release is public
      2 = Enable preview builds
#>

$DesiredValue = 0   # <-- must match remediation script

$MdmPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
$GpoPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

function Get-RegValue($Path, $Name) {
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

$mdmValue   = Get-RegValue $MdmPath 'ManagePreviewBuilds'
$gpoEnabled = Get-RegValue $GpoPath 'ManagePreviewBuilds'
$gpoValue   = Get-RegValue $GpoPath 'ManagePreviewBuildsPolicyValue'

$issues = @()
if ($mdmValue   -ne $DesiredValue) { $issues += "MDM ManagePreviewBuilds=$mdmValue" }
if ($gpoEnabled -ne 1)             { $issues += "GPO ManagePreviewBuilds=$gpoEnabled" }
if ($gpoValue   -ne $DesiredValue) { $issues += "GPO ManagePreviewBuildsPolicyValue=$gpoValue" }

if ($issues.Count -eq 0) {
    Write-Output "Compliant: MDM=$mdmValue, GPO enabled=$gpoEnabled, GPO value=$gpoValue"
    exit 0
}

Write-Output "Not compliant (want $DesiredValue): $($issues -join '; ')"
exit 1