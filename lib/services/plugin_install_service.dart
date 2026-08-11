import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef PluginAssetLoader = Future<String> Function(String assetPath);

class PluginInstallResult {
  const PluginInstallResult({
    required this.pluginDirectory,
    this.marketplaceFile,
  });

  final Directory pluginDirectory;
  final File? marketplaceFile;
}

class PluginInstallService {
  PluginInstallService({
    Directory? homeDirectory,
    Directory? exportRoot,
    PluginAssetLoader? assetLoader,
  }) : _homeDirectory = homeDirectory,
       _exportRoot = exportRoot,
       _assetLoader = assetLoader ?? rootBundle.loadString;

  static const pluginName = 'checkpoint-autosave';
  static const marketplaceName = 'personal';

  static const Map<String, String> assetFiles = {
    'plugins/checkpoint-autosave/.codex-plugin/plugin.json':
        '.codex-plugin/plugin.json',
    'plugins/checkpoint-autosave/.mcp.json': '.mcp.json',
    'plugins/checkpoint-autosave/hooks/hooks.json': 'hooks/hooks.json',
    'plugins/checkpoint-autosave/scripts/checkpoint_after_edit.py':
        'scripts/checkpoint_after_edit.py',
    'plugins/checkpoint-autosave/scripts/test_checkpoint_after_edit.py':
        'scripts/test_checkpoint_after_edit.py',
    'plugins/checkpoint-autosave/skills/checkpoint-autosave/SKILL.md':
        'skills/checkpoint-autosave/SKILL.md',
  };

  final Directory? _homeDirectory;
  final Directory? _exportRoot;
  final PluginAssetLoader _assetLoader;

  Future<PluginInstallResult> installDirect() async {
    final home = _homeDirectory ?? _resolveHomeDirectory();
    final marketplaceRoot = Directory(p.join(home.path, '.agents', 'plugins'));
    final pluginDirectory = Directory(
      p.join(marketplaceRoot.path, 'plugins', pluginName),
    );
    await _writePlugin(pluginDirectory);

    final marketplaceFile = File(
      p.join(marketplaceRoot.path, 'marketplace.json'),
    );
    await _upsertMarketplace(marketplaceFile);
    await _enablePlugin(File(p.join(home.path, '.codex', 'config.toml')));

    return PluginInstallResult(
      pluginDirectory: pluginDirectory,
      marketplaceFile: marketplaceFile,
    );
  }

  Future<PluginInstallResult> exportForCodex() async {
    final root = _exportRoot ?? await _defaultExportRoot();
    final pluginDirectory = Directory(p.join(root.path, pluginName));
    await _writePlugin(pluginDirectory);
    return PluginInstallResult(pluginDirectory: pluginDirectory);
  }

  String buildInstallPrompt(Directory pluginDirectory) =>
      '请安装这个本地 Codex 插件：${pluginDirectory.path}\n\n'
      '插件名是 $pluginName。请将它加入当前用户的 personal marketplace，'
      '启用插件并保留已有 Codex 配置。安装完成后告诉我是否需要重启 Codex、'
      '是否需要授权 hooks，以及 Checkpoint 桌面程序是否必须保持运行。';

  Future<void> _writePlugin(Directory destination) async {
    for (final entry in assetFiles.entries) {
      final file = File(p.join(destination.path, entry.value));
      await file.parent.create(recursive: true);
      await _writeTextAtomically(file, await _assetLoader(entry.key));
    }
  }

  Future<void> _upsertMarketplace(File file) async {
    Map<String, dynamic> marketplace;
    if (await file.exists()) {
      try {
        marketplace =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } on Object catch (error) {
        throw PluginInstallException(
          '无法解析现有 personal marketplace：${file.path}\n$error',
        );
      }
    } else {
      marketplace = {
        'name': marketplaceName,
        'interface': {'displayName': 'Personal'},
        'plugins': <dynamic>[],
      };
    }

    final name = marketplace['name'];
    if (name != marketplaceName) {
      throw PluginInstallException(
        '现有 marketplace 名称是 $name，预期为 $marketplaceName。',
      );
    }
    final rawPlugins = marketplace['plugins'];
    if (rawPlugins is! List) {
      throw const PluginInstallException('personal marketplace 缺少 plugins 列表。');
    }

    final pluginEntry = <String, dynamic>{
      'name': pluginName,
      'source': {'source': 'local', 'path': './plugins/$pluginName'},
      'policy': {'installation': 'AVAILABLE', 'authentication': 'ON_INSTALL'},
      'category': 'Productivity',
    };
    final index = rawPlugins.indexWhere(
      (item) => item is Map && item['name'] == pluginName,
    );
    if (index >= 0) {
      rawPlugins[index] = pluginEntry;
    } else {
      rawPlugins.add(pluginEntry);
    }
    await file.parent.create(recursive: true);
    await _writeTextAtomically(
      file,
      '${const JsonEncoder.withIndent('  ').convert(marketplace)}\n',
    );
  }

  Future<void> _enablePlugin(File file) async {
    final current = await file.exists() ? await file.readAsString() : '';
    final updated = enablePluginInConfig(current);
    if (updated == current) return;
    await file.parent.create(recursive: true);
    await _writeTextAtomically(file, updated);
  }

  Future<Directory> _defaultExportRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Checkpoint', 'plugin-export'));
  }

  Directory _resolveHomeDirectory() {
    final path =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (path == null || path.trim().isEmpty) {
      throw const PluginInstallException('无法确定当前用户目录。');
    }
    return Directory(path);
  }

  Future<void> _writeTextAtomically(File file, String content) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

String enablePluginInConfig(String content) {
  const header = '[plugins."checkpoint-autosave@personal"]';
  final newline = content.contains('\r\n') ? '\r\n' : '\n';
  final hadTrailingNewline = content.endsWith('\n');
  final lines = content.replaceAll('\r\n', '\n').split('\n');
  if (hadTrailingNewline && lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }

  final sectionStart = lines.indexWhere((line) => line.trim() == header);
  if (sectionStart < 0) {
    if (lines.isNotEmpty && lines.any((line) => line.isNotEmpty)) lines.add('');
    lines
      ..add(header)
      ..add('enabled = true');
  } else {
    var sectionEnd = lines.length;
    for (var index = sectionStart + 1; index < lines.length; index++) {
      if (lines[index].trimLeft().startsWith('[')) {
        sectionEnd = index;
        break;
      }
    }
    final enabledIndex =
        List.generate(
              sectionEnd - sectionStart - 1,
              (offset) => sectionStart + 1 + offset,
            )
            .where((index) => RegExp(r'^\s*enabled\s*=').hasMatch(lines[index]))
            .firstOrNull;
    if (enabledIndex == null) {
      lines.insert(sectionStart + 1, 'enabled = true');
    } else {
      lines[enabledIndex] = 'enabled = true';
    }
  }
  return '${lines.join(newline)}$newline';
}

class PluginInstallException implements Exception {
  const PluginInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
