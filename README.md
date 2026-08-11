# Checkpoint
![alt text](docs/potato.png)
一个本地 Git 快照工具，设计用来给 Codex 擦屁股，不过任何有 Git 的项目都能手动使用，也可以接入支持 HTTP MCP 的其他工具。

基本用法就是在 AI 改代码前留个快照，改坏了随时恢复。

快照会保存已暂存、未暂存和未被忽略的新文件。恢复时不会移动 `HEAD`、切换分支或修改 stash，恢复操作并不会删除快照，你可以在任意快照间随意切换。

## 使用

目前支持 Windows，需要本机已安装 Git。

```powershell
flutter run -d windows
```

也可以直接打开指定仓库：

```powershell
checkpoint.exe C:\path\to\repository
```

打开仓库后，点击“创建快照”即可。需要回退时选中快照并还原。

## Codex 自动保存

应用内可以安装附带的 Codex 插件。安装后，只要一轮对话修改了工作区，插件就会在该轮结束时自动创建一次快照
。
注意：stop 钩子是作为 AI 忘记创建 checkpoint 的提醒器，这个仅需要在AI经常忘记创建的时候开启

安装后需要重启 Codex；自动保存期间需要保持 Checkpoint 运行。

## MCP

Checkpoint 运行时会在本机提供 MCP 服务：

```text
http://127.0.0.1:47173/mcp
```

提供两个工具：

- `checkpoint_create_snapshot`：创建快照
- `checkpoint_get_latest_snapshot`：查询最新快照

把这个地址配进任何支持 HTTP MCP 的客户端即可使用。

## 注意

- 仓库至少要有一次提交。
- `.gitignore` 排除的文件不会进入快照。
- 恢复会覆盖当前未提交修改，并清理未被忽略的未跟踪文件。
- 快照适合临时兜底，长期保存仍然应该正常 commit。

## 开发

```powershell
flutter pub get
flutter test
flutter analyze
```
