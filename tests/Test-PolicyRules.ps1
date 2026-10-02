param([switch]$SkipParserCheck)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\PolicyRules.psm1') -Force
$known = Get-DotPolicyFingerprint
$script:passed = 0
function New-ExamplePolicy {
    @{
        PolicyID = $known.PolicyId; BasePolicyID = $known.PolicyId
        FriendlyName = $known.FriendlyName; VersionString = $known.Version
        IsSystemPolicy = $false; IsSignedPolicy = $false; IsEnforced = $true
        IsAuthorized = $true; IsOnDisk = $true
        PolicyOptions = @('Enabled:UMCI', 'Enabled:Unsigned System Integrity Policy')
    }
}
function Assert-Decision {
    param([string]$Name, [object[]]$Policies, [AllowNull()][string]$Hash, [bool]$Expected)
    $result = Test-DotPolicyEligibility -Policies $Policies -FileHash $Hash
    if ($result.Eligible -ne $Expected) { throw ('FAIL: ' + $Name) }
    if (-not $Expected -and $result.Reasons.Count -eq 0) { throw ('Missing refusal reason: ' + $Name) }
    $script:passed++
    Write-Output ('PASS: ' + $Name)
}
Assert-Decision 'exact tested fingerprint' @((New-ExamplePolicy)) $known.Sha256 $true
Assert-Decision 'absent target' @() $known.Sha256 $false
Assert-Decision 'duplicate target' @((New-ExamplePolicy),(New-ExamplePolicy)) $known.Sha256 $false
Assert-Decision 'unknown hash' @((New-ExamplePolicy)) ('0' * 64) $false
Assert-Decision 'missing file hash' @((New-ExamplePolicy)) $null $false
foreach ($field in @('IsSystemPolicy','IsSignedPolicy')) {
    $policy = New-ExamplePolicy; $policy[$field] = $true
    Assert-Decision ($field + ' must refuse') @($policy) $known.Sha256 $false
    $policy = New-ExamplePolicy; $policy.Remove($field)
    Assert-Decision ($field + ' missing must refuse') @($policy) $known.Sha256 $false
    $policy = New-ExamplePolicy; $policy[$field] = 'false'
    Assert-Decision ($field + ' string is not a boolean') @($policy) $known.Sha256 $false
}
foreach ($field in @('IsEnforced','IsAuthorized','IsOnDisk')) {
    $policy = New-ExamplePolicy; $policy[$field] = $false
    Assert-Decision ($field + ' false must refuse') @($policy) $known.Sha256 $false
    $policy = New-ExamplePolicy; $policy.Remove($field)
    Assert-Decision ($field + ' missing must refuse') @($policy) $known.Sha256 $false
}
foreach ($field in @('PolicyID','BasePolicyID','FriendlyName','VersionString')) {
    $policy = New-ExamplePolicy; $policy[$field] = 'unrelated'
    Assert-Decision ($field + ' mismatch') @($policy) $known.Sha256 $false
}
$policy = New-ExamplePolicy; $policy.PolicyOptions = @()
Assert-Decision 'UMCI absent' @($policy) $known.Sha256 $false
$policy = New-ExamplePolicy; $policy.PolicyOptions += 'Enabled:Audit Mode'
Assert-Decision 'audit-only policy' @($policy) $known.Sha256 $false
$policy = New-ExamplePolicy; $policy.PolicyOptions += 'Disabled:Script Enforcement'
Assert-Decision 'script enforcement already disabled' @($policy) $known.Sha256 $false
$unrelated = New-ExamplePolicy; $unrelated.PolicyID = '00000000-0000-0000-0000-000000000000'; $unrelated.IsSystemPolicy = $true
Assert-Decision 'unrelated system policy does not authorize removal of itself' @($unrelated) $known.Sha256 $false
Assert-Decision 'unrelated policy alongside eligible target' @($unrelated,(New-ExamplePolicy)) $known.Sha256 $true
# Parser validation without executing the repair script or calling CiTool.
if (-not $SkipParserCheck) {
    $tokens = $null; $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Repair-DotLocalWorkspace.ps1'),[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
}
Write-Output ('All ' + $script:passed + ' eligibility checks passed. No security changes were made.')
