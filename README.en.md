# dot-local-workspace-fix

A documented Windows fix for **one verified cause** of ChatGPT dot local-task creation failing with `DesktopTaskWorkspaceUnavailableError`, despite the computer appearing connected and authorized.

[中文](README.md) · [Redacted case report](docs/verified-case.md) · [MIT License](LICENSE)

## Observed cause and result

An additional unsigned App Control / WDAC policy forced Windows PowerShell into `ConstrainedLanguage`. During workspace preparation, the local Work executor spawned PowerShell, which exited with code 1 before file reading.

After removing only the identified policy with a verified backup, fresh PowerShell used `FullLanguage`. The workspace helper launched Node successfully; both exited with code 0. A newly created dot task returned an ID and read a local 237-byte probe whose contents and SHA-256 matched an independent local read.

This is a single-machine result, not a universal fix for this error. Other client, server, networking, or workspace causes remain possible.

## Diagnose first

In Windows PowerShell opened manually from the Start menu:

```powershell
$ExecutionContext.SessionState.LanguageMode
```

Download and review the repository. From an administrator Windows PowerShell window in its directory:

```powershell
.\Repair-DotLocalWorkspace.ps1
```

The default mode is read-only, makes no backups, changes no policies, and uploads nothing. Administrator access is needed when CiTool refuses inventory access.

The tool accepts only this exact tested fingerprint:

| Attribute | Required value |
| --- | --- |
| Policy / Base Policy ID | `31351756-3f24-4963-8380-4e7602335aae` |
| Friendly name | `Microsoft Power Manager` |
| Version | `1.0.3.7` |
| SHA-256 | `537DBADA7974F8C17AFFD6A6C8BBDE4474E8CA129AF735A98C5553ECF8F72E72` |
| Metadata | Active, authorized, on disk, unsigned, non-system |
| Options | UMCI enabled, no audit-only mode, script enforcement not disabled |

A matching ID or name alone does not establish matching contents or malware. The hash is an eligibility fingerprint, not a general malware signature. Unknown hashes, duplicate targets, missing metadata, and ambiguous boolean fields are refused.

## Opt-in repair

Confirm the policy's purpose and deployment source, particularly on managed computers. Group Policy or MDM may redeploy it. [Microsoft policy-removal guidance](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/deployment/disable-appcontrol-policies)

Preview, then explicitly opt in:

```powershell
.\Repair-DotLocalWorkspace.ps1 -Apply -WhatIf
.\Repair-DotLocalWorkspace.ps1 -Apply
```

The script requests confirmation, checks live inventory again, backs up the policy and verifies its hash, calls Windows' built-in `CiTool -rp` for that single ID, saves before/after inventory and the tool result, and verifies removal. Default backup location: `%LOCALAPPDATA%\DotLocalWorkspaceFix\backups`; optionally specify `-BackupDirectory`.

Windows 11 22H2 or later is required. Unsigned policy removal can take effect without restart on 24H2 or later; earlier versions may require a restart. The tool does not reboot, retry failed removal, directly delete system files, disable Defender, modify another policy, change proxy/TUN settings, weaken sandbox permissions, or clear `.codex`. It does not automatically restore a policy with unknown provenance. [CiTool reference](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/citool-commands)

## Verify the actual workflow

Open fresh PowerShell and check language mode. With working network access, ask dot to create one new local task that reads a harmless probe. Independently compare its actual contents, byte count, SHA-256, and execution time. Inventory success or an existing conversation reading the file is insufficient.

The verified case used the same temporary TUN connectivity before and after removal, then restored its prior state. This does not establish that unrelated network problems, follow-up tasks, or every dot feature are fixed.

## Provenance and privacy

The same policy path appears in [Elastic's RONINGLOADER research](https://security-labs.elastic.co/security-labs/roningloader), but this case's file hash differs and its origin remains unconfirmed. Removal is not a malware cleanup or evidence that a computer is uncompromised.

The repository includes no raw policy binaries, original logs, email addresses, computer identities, actual task IDs, or credentials. Local backup inventories can contain device information: do not upload them unredacted.

This project is unaffiliated with OpenAI. [Microsoft documents PowerShell's behavior under App Control](https://learn.microsoft.com/en-us/powershell/scripting/security/app-control/application-control).

## Tests

```powershell
.\tests\Test-PolicyRules.ps1
```

Tests exercise refusal cases and parse the repair script without calling CiTool or changing policies. CI runs on Windows PowerShell 5.1 and PowerShell 7.
