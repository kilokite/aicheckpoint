import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/snapshot.dart';

class CheckpointSidebar extends StatelessWidget {
  const CheckpointSidebar({
    super.key,
    required this.repository,
    required this.recentRepositories,
    required this.snapshotCount,
    required this.mcpOnline,
    required this.mcpError,
    required this.onOpen,
    required this.onSelectRecent,
    required this.onInstallPlugin,
    required this.onCopyMcpUrl,
  });

  final RepositoryInfo? repository;
  final List<String> recentRepositories;
  final int snapshotCount;
  final bool mcpOnline;
  final String? mcpError;
  final VoidCallback onOpen;
  final ValueChanged<String> onSelectRecent;
  final VoidCallback onInstallPlugin;
  final VoidCallback onCopyMcpUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: const Color(0xFF20231F),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('打开目录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4C504A)),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                ),
              ),
            ),
            if (repository != null) ...[
              const SizedBox(height: 22),
              const _SidebarLabel('当前仓库'),
              _RepositoryTile(
                path: repository!.path,
                selected: true,
                trailing: snapshotCount.toString(),
                onTap: () {},
              ),
            ],
            if (recentRepositories.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SidebarLabel('最近打开'),
              for (final path in recentRepositories)
                if (repository == null ||
                    p.normalize(path) != p.normalize(repository!.path))
                  _RepositoryTile(
                    path: path,
                    onTap: () => onSelectRecent(path),
                  ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextButton.icon(
                onPressed: onInstallPlugin,
                icon: const Icon(Icons.extension_outlined, size: 18),
                label: const Text('安装 Codex 插件'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD7DAD5),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 14),
              child: Tooltip(
                message: mcpError ?? '复制 MCP 地址',
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: mcpOnline
                            ? const Color(0xFF58C994)
                            : const Color(0xFFCC655C),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'MCP · 127.0.0.1:47173',
                        style: TextStyle(
                          color: Color(0xFFADB1AA),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCopyMcpUrl,
                      tooltip: '复制 MCP 地址',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.copy,
                        size: 15,
                        color: Color(0xFFADB1AA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarLabel extends StatelessWidget {
  const _SidebarLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF8D928A),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({
    required this.path,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final String path;
  final VoidCallback onTap;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    child: Material(
      color: selected ? const Color(0xFF30362F) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 17,
                color: selected
                    ? const Color(0xFF58C994)
                    : const Color(0xFFADB1AA),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFD0D3CD),
                    fontSize: 13,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: Color(0xFF8D928A),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
