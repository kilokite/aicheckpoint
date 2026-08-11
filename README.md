# Checkpoint

Checkpoint 是一个面向 AI 编程流程的本地 Git 快照管理器。它使用
`git stash create` 生成不可见的提交对象，由应用在仓库外保存对象哈希；不会写入
`refs/stash`、移动 `HEAD` 或创建分支、标签。

## 运行

```powershell
flutter run -d windows
```

从目标仓库启动：

```powershell
checkpoint.exe C:\path\to\repository
```

若已将程序目录加入 `PATH`，可在仓库中直接运行：

```powershell
checkpoint.exe
```

也可以传入任意仓库路径：`checkpoint.exe C:\path\to\repository`。

也可以启动后点击“打开目录”。快照元数据保存在 Windows 应用数据目录，不会向目标仓库写入配置文件。

## 行为

- 快照包含已跟踪修改、暂存区状态以及未跟踪但未被 Git 忽略的文件。
- 创建快照使用临时 index，真实 index、工作区、HEAD 和 Git refs 保持不变。
- 还原会替换当前修改和未跟踪文件，但不会移动 HEAD 或分支。
- `.gitignore` 匹配的文件不进入快照，也不会在还原时被清理。
- 仓库存在未解决的合并冲突时，Git 无法写出 index tree，应用会拒绝创建快照。

按设计，应用只保存对象哈希，没有创建防止 Git GC 的引用。

## MCP 服务

应用运行时会在本机启动 Streamable HTTP MCP 服务：

```text
http://127.0.0.1:47173/mcp
```

把这个 URL 添加到支持 HTTP MCP 的客户端即可。常见客户端配置形态如下：

```json
{
  "mcpServers": {
    "checkpoint": {
      "url": "http://127.0.0.1:47173/mcp"
    }
  }
}
```

服务提供两个不可删改的工具：

- `checkpoint_create_snapshot`：创建项目快照。
- `checkpoint_get_latest_snapshot`：只读查询项目的最新快照，供自动保存插件去重。

创建工具参数为：

- `project_path`：必填，Git 项目的绝对路径。
- `title`：可选，最长 80 个字符的快照名称。

MCP 不暴露删除、重命名、还原或修改快照的工具。服务仅绑定
`127.0.0.1`，并启用本地 Origin 限制；Checkpoint 退出后服务随之关闭。

## Codex 自动保存插件

插件源码位于 `plugins/checkpoint-autosave`，并作为资源打包进 Windows 产物。
桌面应用左侧的“安装 Codex 插件”提供两种方式：

- 直接安装：将插件复制到当前用户的 personal marketplace，并在
  `~/.codex/config.toml` 中启用 `checkpoint-autosave@personal`。
- 让 Codex 安装：将完整插件源码导出到 Checkpoint 应用数据目录，并生成一段带绝对
  路径的安装提示词。

安装后需要重新启动 Codex，并在首次使用时确认 hook 权限。自动保存期间必须保持
Checkpoint 桌面应用运行；目标机器还需要在 `PATH` 中提供 Git 和 Python。
