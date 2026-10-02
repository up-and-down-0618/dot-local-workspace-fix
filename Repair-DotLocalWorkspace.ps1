#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$Apply,
    [string]$BackupDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This tool supports Windows only.' }
Import-Module (Join-Path $PSScriptRoot 'PolicyRules.psm1') -Force
$known = Get-DotPolicyFingerprint
$ciTool = Join-Path $env:SystemRoot 'System32\CiTool.exe'
$sourcePath = Join-Path $env:SystemRoot ('System32\CodeIntegrity\CiPolicies\Active\{' + $known.PolicyId + '}.cip')
if (-not (Test-Path -LiteralPath $ciTool -PathType Leaf)) { throw 'CiTool is unavailable. Windows 11 22H2 or later is required.' }

function Read-CiInventory {
    $raw = & $ciTool -lp -json
    $code = $LASTEXITCODE
    $value = $raw | ConvertFrom-Json
    if ($code -ne 0 -or $value.OperationResult -ne 0 -or $null -eq $value.Policies) {
        throw 'CiTool inventory failed. Run an administrator PowerShell window. No policy was changed.'
    }
    return $value
}
function Read-SourceHash {
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        return (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
    }
    return $null
}
function Assert-CurrentEligibility {
    param($Inventory, $Hash)
    $check = Test-DotPolicyEligibility -Policies @($Inventory.Policies) -FileHash $Hash
    if (-not $check.Eligible) { throw ('Refusing to remove policy: ' + ($check.Reasons -join ' ')) }
}

Write-Host ('PowerShell language mode: ' + $ExecutionContext.SessionState.LanguageMode)
$before = Read-CiInventory
$assessment = Test-DotPolicyEligibility -Policies @($before.Policies) -FileHash (Read-SourceHash)
@{
    LanguageMode = $ExecutionContext.SessionState.LanguageMode.ToString()
    Candidate = $assessment.Policy
    EligibleForThisSpecificRepair = $assessment.Eligible
    Reasons = $assessment.Reasons
    ExpectedSha256 = $assessment.ExpectedSha256
} | ConvertTo-Json -Depth 8 | Write-Output
if (-not $Apply) {
    Write-Host 'Read-only diagnosis completed. Nothing was removed, backed up, or uploaded.'
    return
}
Assert-CurrentEligibility -Inventory $before -Hash (Read-SourceHash)
if (-not $PSCmdlet.ShouldProcess($known.PolicyId, 'Back up and remove this exact unsigned non-system App Control policy')) { return }

# Recheck after the confirmation prompt; no bypass for signed, system, or unknown policies.
$before = Read-CiInventory
Assert-CurrentEligibility -Inventory $before -Hash (Read-SourceHash)
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'Specify -BackupDirectory; LOCALAPPDATA is unavailable.' }
    $BackupDirectory = Join-Path $env:LOCALAPPDATA 'DotLocalWorkspaceFix\backups'
}
$ancestor = $BackupDirectory
while (-not (Test-Path -LiteralPath $ancestor)) {
    $parent = Split-Path -Path $ancestor -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = '.' }
    if ($parent -eq $ancestor) { throw 'Cannot resolve backup directory.' }
    $ancestor = $parent
}
$resolvedAncestor = Resolve-Path -LiteralPath $ancestor
if ($resolvedAncestor.Provider.Name -ne 'FileSystem') { throw 'Backups require a filesystem directory.' }
$windowsDirectory = (Resolve-Path -LiteralPath $env:SystemRoot).ProviderPath
if ($resolvedAncestor.ProviderPath -eq $windowsDirectory -or $resolvedAncestor.ProviderPath -like ($windowsDirectory + '\*')) {
    throw 'Backups must be outside the Windows system directory.'
}
if ((Test-Path -LiteralPath $BackupDirectory) -and -not (Test-Path -LiteralPath $BackupDirectory -PathType Container)) {
    throw 'BackupDirectory points to a file.'
}
$base = (New-Item -ItemType Directory -Path $BackupDirectory -Force).FullName
$runName = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + (Get-Random -Minimum 1000 -Maximum 9999)
$runDirectory = Join-Path $base $runName
if (Test-Path -LiteralPath $runDirectory) { throw 'Backup run directory already exists; no policy was changed.' }
$null = New-Item -ItemType Directory -Path $runDirectory
$backupPath = Join-Path $runDirectory ('{' + $known.PolicyId + '}.cip')
Copy-Item -LiteralPath $sourcePath -Destination $backupPath -ErrorAction Stop
if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne $known.Sha256) {
    throw 'Backup hash mismatch. Removal was not attempted.'
}
$before | ConvertTo-Json -Depth 12 | Out-File -LiteralPath (Join-Path $runDirectory 'before.json') -Encoding utf8
Assert-CurrentEligibility -Inventory (Read-CiInventory) -Hash (Read-SourceHash)
Write-Host ('Verified backup: ' + $backupPath)

# The only security mutation in this tool. Never delete files or alter other policies.
$removalRaw = & $ciTool -rp ('{' + $known.PolicyId + '}') -json
$removalExit = $LASTEXITCODE
$removalRaw | Out-File -LiteralPath (Join-Path $runDirectory 'removal-result.json') -Encoding utf8
$removal = $removalRaw | ConvertFrom-Json
if ($removalExit -ne 0 -or $removal.OperationResult -ne 0) {
    throw ('CiTool removal failed. No retry or reboot was attempted. Evidence: ' + $runDirectory)
}
$after = Read-CiInventory
$after | ConvertTo-Json -Depth 12 | Out-File -LiteralPath (Join-Path $runDirectory 'after.json') -Encoding utf8
$remaining = @($after.Policies | Where-Object { $_.PolicyID -eq $known.PolicyId -and $_.IsEnforced -eq $true })
if ($remaining.Count -gt 0) { throw ('Policy remains active. Inspect evidence; no automatic retry: ' + $runDirectory) }
$beforeOthers = @($before.Policies | Where-Object { $_.PolicyID -ne $known.PolicyId })
$afterOthers = @($after.Policies | Where-Object { $_.PolicyID -ne $known.PolicyId })
$changes = @(Compare-Object -ReferenceObject $beforeOthers -DifferenceObject $afterOthers -Property PolicyID,IsSystemPolicy,IsSignedPolicy,IsEnforced,FriendlyName)
if ($changes.Count -gt 0) { Write-Warning 'Other policy metadata changed concurrently. Review the saved inventories.' }
Write-Host ('Target policy is no longer active. Evidence: ' + $runDirectory)
Write-Host 'Open a fresh PowerShell window to check LanguageMode, then perform one actual dot local-file test.'
Write-Host 'Removal alone does not establish that dot works or that the computer is free of malware.'
