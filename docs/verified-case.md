# Redacted verification: 2026-10-02

## Symptom

Windows ChatGPT desktop reported a connected, attached, authorized computer. Repeated new local-task creation failed before execution:

```text
DesktopTaskWorkspaceUnavailableError:
The desktop could not prepare a task workspace. Update or reconnect it before creating the task.

error_code: CONFLICT
error_data.type: desktop_task_workspace_unavailable
```

Changing the working directory, reconnecting, and enabling a working TUN network path did not resolve that creation failure in the recorded tests.

## Controlled comparison

| Observation | Before removal | After removal |
| --- | --- | --- |
| Network used for dot probe | Working temporary TUN connection | Same temporary TUN connection |
| Desktop application | Same running app | Same running app; no reinstall/restart |
| Working directory | Existing Windows directory with two spaces in its name | Same directory |
| Native local `taskWorkspace/prepare` probe | Successful, signature verified | Not used as the final proof |
| New Windows PowerShell | `ConstrainedLanguage` | `FullLanguage` |
| Wldp global policy result | `0x80000005` | `0x80000000` |
| Work executor's PowerShell | Exit code `1` | Starts Node; both exit code `0` |
| New dot local task | No task ID returned | Task ID returned; completed |
| Actual file read | Not reached | 237 bytes; contents and SHA-256 independently matched |

Only the unsigned, non-system policy documented in the README was removed. CiTool returned `OperationResult=0`; other policy metadata was unchanged in the comparison. The policy binary was backed up and its hash verified. TUN was restored to its original disabled state after the probe.

The successful file read used real Windows PowerShell execution and returned actual file bytes. Expected contents and hash were not supplied to dot before testing. This is the evidence for the repaired workflow, beyond a "connected" indicator.

## Limits

- One verified machine, one post-removal creation/read test.
- Process sampling was approximately 30ms; shorter processes could be missed. The process watcher did not collect command contents or credentials.
- The exact failed preparation command's stderr was not recovered. The changed language mode, successful helper process, and successful new task support the intervention; they do not explain every internal implementation detail.
- Desktop build recorded during investigation: release `26.930.21537`, package `26.930.2377.0`; Windows 11 25H2. These are observations, not minimum required versions for dot.
- The policy's provenance was not established; a shared GUID is not an infection diagnosis.
- No claim about all dot features, later conversation turns, VPN-free operation, or complete malware removal.

Account identifiers, local usernames and private paths, actual task IDs, probe contents, complete policy inventories, raw desktop logs, and policy binaries are intentionally omitted.
