# Pure eligibility rules. This module never calls CiTool or changes the machine.
function Get-DotPolicyFingerprint {
    @{
        PolicyId = '31351756-3f24-4963-8380-4e7602335aae'
        FriendlyName = 'Microsoft Power Manager'
        Version = '1.0.3.7'
        Sha256 = '537DBADA7974F8C17AFFD6A6C8BBDE4474E8CA129AF735A98C5553ECF8F72E72'
    }
}

function Test-DotPolicyEligibility {
    param([AllowEmptyCollection()][object[]]$Policies = @(), [AllowNull()][string]$FileHash)
    $known = Get-DotPolicyFingerprint
    $matches = @($Policies | Where-Object { $_.PolicyID -eq $known.PolicyId })
    $reasons = @()
    $policy = $null
    if ($matches.Count -ne 1) {
        $reasons += 'Exactly one matching policy is required (absent or duplicate).'
    } else {
        $policy = $matches[0]
        if ($policy.IsSystemPolicy -isnot [bool] -or $policy.IsSystemPolicy -ne $false) { $reasons += 'System policy or unknown system-policy status.' }
        if ($policy.IsSignedPolicy -isnot [bool] -or $policy.IsSignedPolicy -ne $false) { $reasons += 'Signed policy or unknown signature status.' }
        if ($policy.IsEnforced -isnot [bool] -or $policy.IsEnforced -ne $true) { $reasons += 'Policy is not confirmed active.' }
        if ($policy.IsAuthorized -isnot [bool] -or $policy.IsAuthorized -ne $true) { $reasons += 'Policy is not confirmed authorized.' }
        if ($policy.IsOnDisk -isnot [bool] -or $policy.IsOnDisk -ne $true) { $reasons += 'Policy is not confirmed on disk.' }
        if ($policy.BasePolicyID -ne $known.PolicyId) { $reasons += 'Base-policy identity mismatch.' }
        if ($policy.FriendlyName -cne $known.FriendlyName) { $reasons += 'Policy name mismatch.' }
        if ($policy.VersionString -ne $known.Version) { $reasons += 'Policy version mismatch.' }
        if (@($policy.PolicyOptions) -notcontains 'Enabled:UMCI') { $reasons += 'UMCI option is absent.' }
        if (@($policy.PolicyOptions) -contains 'Enabled:Audit Mode') { $reasons += 'Audit-only policy is outside this repair.' }
        if (@($policy.PolicyOptions) -contains 'Disabled:Script Enforcement') { $reasons += 'Script enforcement is already disabled; outside this repair.' }
    }
    if ($FileHash -ne $known.Sha256) { $reasons += 'File SHA-256 is missing or differs from the tested fingerprint.' }
    @{
        Eligible = ($reasons.Count -eq 0)
        Reasons = $reasons
        Policy = $policy
        KnownPolicyId = $known.PolicyId
        ExpectedSha256 = $known.Sha256
    }
}

Export-ModuleMember -Function Get-DotPolicyFingerprint, Test-DotPolicyEligibility
