# ChatGPT dot 本地任务失败：DesktopTaskWorkspaceUnavailableError

Windows 上 ChatGPT dot 显示电脑已连接、已授权，但创建本地任务时报 `DesktopTaskWorkspaceUnavailableError` 的一种已验证修复方法。

[English](README.en.md) · [脱敏复现记录](docs/verified-case.md) · [MIT License](LICENSE)

## 对照报错原文

如果搜索下面这段报错找到了本仓库，先确认你的故障也发生在**准备本地任务工作区**阶段：电脑显示已连接、已绑定、已授权，但没有返回新任务 ID，尚未开始读取文件。

```text
DesktopTaskWorkspaceUnavailableError: The desktop could not prepare a task workspace. Update or reconnect it before creating the task.

error_code: CONFLICT
error_data.type: desktop_task_workspace_unavailable
```

中文常见描述：**dot 无法连接本地电脑、无法创建任务工作区、无法准备任务工作区、电脑已连接但本地任务无法启动**。

本仓库记录的是这一报错中由特定 Windows WDAC / App Control 策略引起的一种已验证原因。相同报错不一定具有相同原因；请先按下文检查 PowerShell `ConstrainedLanguage` 和策略指纹。

## 这份方案解决什么

2026-10-02 的一次实测中，一份额外的、未签名的 WDAC / App Control 策略让 Windows PowerShell 进入 `ConstrainedLanguage`。dot 准备本地工作区时启动的 PowerShell 退出码为 `1`，尚未执行文件读取。

只移除这份已识别并备份的策略后，新的 PowerShell 恢复 `FullLanguage`；dot 的准备进程成功启动 Node，两个进程退出码均为 `0`，新任务成功返回 ID，并实际读取了本机探针文件。内容、237 字节长度和 SHA-256 与独立读取一致。

这是一个案例。相同错误还可能来自其他客户端、服务端、网络或工作区问题；这个工具不会把错误名称当作删除策略的依据。

## 先诊断

在你自己从开始菜单打开的 Windows PowerShell 中运行：

```powershell
$ExecutionContext.SessionState.LanguageMode
```

从 GitHub 下载并检查本仓库代码。在**管理员 Windows PowerShell** 中进入仓库目录，运行默认只读诊断：

```powershell
.\Repair-DotLocalWorkspace.ps1
```

默认模式不创建备份、不移除策略、不上传任何信息。`CiTool` 查询可能需要管理员权限；遇到权限错误会停止。

工具仅识别以下特定指纹：

| 字段 | 必须匹配的值 |
| --- | --- |
| Policy ID / Base Policy ID | `31351756-3f24-4963-8380-4e7602335aae` |
| FriendlyName | `Microsoft Power Manager` |
| VersionString | `1.0.3.7` |
| SHA-256 | `537DBADA7974F8C17AFFD6A6C8BBDE4474E8CA129AF735A98C5553ECF8F72E72` |
| 状态 | 生效、已授权、在磁盘上、未签名、非系统策略 |
| 策略选项 | UMCI 生效，非审计模式，未禁用脚本强制 |

**ID 或名称相同不代表内容相同，也不能据此判定恶意软件。** 这个 SHA-256 是本案例的匹配条件，不是通用恶意软件签名。任何字段缺失、类型不明确、重复策略或文件指纹不同，修复模式都会拒绝移除。

如果你自己、单位管理员或安全软件配置了这份策略，应先确认它的用途和部署来源。集团策略或 MDM 可能重新部署被移除的策略。[微软的移除说明](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/deployment/disable-appcontrol-policies)

## 明确选择后修复

适用于 Windows 11 22H2 及以上，使用系统自带 `CiTool.exe`。先预览：

```powershell
.\Repair-DotLocalWorkspace.ps1 -Apply -WhatIf
```

确认匹配、了解用途，并同意移除该**单一策略**后执行：

```powershell
.\Repair-DotLocalWorkspace.ps1 -Apply
```

脚本会请求确认，重新查询当前策略，保存原始 `.cip` 文件并验证备份 hash，再调用针对该 ID 的 `CiTool -rp`。默认备份目录为当前用户的 `%LOCALAPPDATA%\DotLocalWorkspaceFix\backups`；也可传入 `-BackupDirectory`。

它保存移除前后清单及工具返回值，验证目标不再生效，并比较其他策略元数据。备份失败或状态发生变化时停止；失败不自动重试、不重启，不修改其他策略。Windows 11 24H2 起未签名策略可无需重启移除，旧版本可能需要重启；不要仅凭命令成功就宣布修复。[CiTool 官方参考](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/operations/citool-commands)

脚本不关闭 Defender、不改变代理或 TUN、不修改沙箱权限，不清空 `.codex`。它不自动重新部署来源未明的策略。

## 验证结果

1. 打开新的 Windows PowerShell，重新检查语言模式。
2. 保持原本可用的网络连接，让 dot **新建一次本地任务**，实际读取一个无敏感信息的测试文件。
3. 核对任务 ID、实际内容、字节数、SHA-256 和执行时间；同一对话读文件或旧结果不能代替这次新任务。

原始成功案例使用临时 TUN 连通网络，移除前后网络条件相同，结束后恢复了 TUN 原状态。它证明工作区阻塞解除，**没有证明所有网络问题或所有 dot 功能都已修复**。

如果语言模式或创建任务仍失败，保存错误原文和对应时间，继续查具体原因；不要继续删除其他策略或整体关闭应用控制。

## 策略来源与隐私

同一策略文件路径见于 [Elastic 的 RONINGLOADER 研究](https://security-labs.elastic.co/security-labs/roningloader)，但本案例文件 hash 不同，来源未确认。这份修复不能代替恶意软件排查，也不能证明系统没有活动恶意软件。

本仓库不含原始策略文件、邮箱、电脑标识、真实任务 ID、登录资料或原始桌面日志。脚本在本地生成的完整策略清单和备份可能包含你的设备信息；不要直接公开上传它们。

本项目与 OpenAI 无隶属关系。PowerShell 在系统应用控制下可能进入受限语言模式，详见 [微软说明](https://learn.microsoft.com/en-us/powershell/scripting/security/app-control/application-control)。

## 开发验证

```powershell
.\tests\Test-PolicyRules.ps1
```

测试覆盖可移除指纹、缺失/重复目标、系统/签名策略、非布尔元数据、未知 hash、非生效状态与策略选项变化。测试只调用纯规则并解析脚本，不执行 `CiTool` 或改变策略。GitHub Actions 在 Windows PowerShell 5.1 和 PowerShell 7 下运行。
