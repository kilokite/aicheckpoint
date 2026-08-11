import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/plugin_install_service.dart';

class PluginInstallDialog extends StatefulWidget {
  const PluginInstallDialog({super.key, required this.service});

  final PluginInstallService service;

  @override
  State<PluginInstallDialog> createState() => _PluginInstallDialogState();
}

class _PluginInstallDialogState extends State<PluginInstallDialog> {
  bool _busy = false;
  String? _status;
  String? _error;
  Directory? _exportDirectory;
  String? _installPrompt;

  Future<void> _installDirect() async {
    await _run(() async {
      final result = await widget.service.installDirect();
      if (!mounted) return;
      setState(() {
        _status = '插件已安装到 ${result.pluginDirectory.path}。重启 Codex 后生效。';
        _exportDirectory = null;
        _installPrompt = null;
      });
    });
  }

  Future<void> _export() async {
    await _run(() async {
      final result = await widget.service.exportForCodex();
      if (!mounted) return;
      setState(() {
        _exportDirectory = result.pluginDirectory;
        _installPrompt = widget.service.buildInstallPrompt(
          result.pluginDirectory,
        );
        _status = '插件源码已导出，可把下面的提示词交给 Codex。';
      });
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPrompt() async {
    final prompt = _installPrompt;
    if (prompt == null) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) setState(() => _status = '安装提示词已复制。');
  }

  Future<void> _openExportDirectory() async {
    final directory = _exportDirectory;
    if (directory == null) return;
    try {
      await Process.start('explorer.exe', [directory.path]);
    } catch (error) {
      if (mounted) setState(() => _error = '无法打开目录：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.extension_outlined, size: 22),
          SizedBox(width: 10),
          Text('安装 Codex 插件'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '直接安装',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                '复制插件到当前用户的 personal marketplace 并启用。不会覆盖其他插件配置。',
                style: TextStyle(fontSize: 12, color: Color(0xFF666B64)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('install-plugin-direct'),
                  onPressed: _busy ? null : _installDirect,
                  icon: const Icon(Icons.install_desktop, size: 19),
                  label: const Text('直接安装到 Codex'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(height: 1),
              ),
              const Text(
                '让 Codex 安装',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                '把插件源码导出到应用数据目录，再生成一段带绝对路径的安装提示词。',
                style: TextStyle(fontSize: 12, color: Color(0xFF666B64)),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('export-plugin-for-codex'),
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.folder_copy_outlined, size: 19),
                  label: const Text('导出并生成提示词'),
                ),
              ),
              if (_installPrompt case final prompt?) ...[
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F1EE),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            prompt,
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _copyPrompt,
                            tooltip: '复制安装提示词',
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                          IconButton(
                            onPressed: _openExportDirectory,
                            tooltip: '打开插件目录',
                            icon: const Icon(Icons.folder_open, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_status case final status?) ...[
                const SizedBox(height: 14),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF16855B),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 14),
                Text(
                  error,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9D2B2B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
