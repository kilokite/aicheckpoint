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
