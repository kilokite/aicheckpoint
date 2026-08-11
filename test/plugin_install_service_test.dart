import 'dart:convert';
import 'dart:io';

import 'package:checkpoint/services/plugin_install_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory homeDirectory;
  late Directory exportRoot;
  late PluginInstallService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'checkpoint_plugin_test_',
    );
    homeDirectory = Directory(p.join(temporaryDirectory.path, 'home'));
    exportRoot = Directory(p.join(temporaryDirectory.path, 'export'));
    service = PluginInstallService(
      homeDirectory: homeDirectory,
      exportRoot: exportRoot,
      assetLoader: (path) async => 'asset:$path\n',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'direct install preserves marketplace entries and enables plugin',
    () async {
      final marketplaceFile = File(
        p.join(homeDirectory.path, '.agents', 'plugins', 'marketplace.json'),
      );
      await marketplaceFile.parent.create(recursive: true);
      await marketplaceFile.writeAsString(
        jsonEncode({
          'name': 'personal',
          'interface': {'displayName': 'My plugins'},
          'plugins': [
            {
              'name': 'existing-plugin',
              'source': {
                'source': 'local',
                'path': './plugins/existing-plugin',
              },
              'policy': {
                'installation': 'AVAILABLE',
                'authentication': 'ON_INSTALL',
              },
              'category': 'Productivity',
            },
          ],
        }),
      );
      final configFile = File(
        p.join(homeDirectory.path, '.codex', 'config.toml'),
      );
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        'model = "gpt-5"\r\n\r\n'
        '[plugins."checkpoint-autosave@personal"]\r\n'
        'enabled = false\r\n\r\n'
        '[features]\r\n'
        'example = true\r\n',
      );

      final result = await service.installDirect();

      for (final relativePath in PluginInstallService.assetFiles.values) {
        expect(
          File(p.join(result.pluginDirectory.path, relativePath)).existsSync(),
          isTrue,
        );
      }
      final marketplace =
          jsonDecode(await marketplaceFile.readAsString())
              as Map<String, dynamic>;
      final plugins = marketplace['plugins'] as List<dynamic>;
      expect(plugins, hasLength(2));
      expect(
        plugins.where((item) => item['name'] == 'checkpoint-autosave'),
        hasLength(1),
      );
      final config = await configFile.readAsString();
      expect(config, contains('model = "gpt-5"\r\n'));
      expect(config, contains('enabled = true\r\n'));
      expect(config, contains('[features]\r\nexample = true'));
    },
  );

  test('export writes a standalone source directory and prompt', () async {
    final result = await service.exportForCodex();
    expect(
      result.pluginDirectory.path,
      p.join(exportRoot.path, 'checkpoint-autosave'),
    );
    expect(
      File(
        p.join(result.pluginDirectory.path, '.codex-plugin', 'plugin.json'),
      ).existsSync(),
      isTrue,
    );
    final prompt = service.buildInstallPrompt(result.pluginDirectory);
    expect(prompt, contains(result.pluginDirectory.path));
    expect(prompt, contains('personal marketplace'));
  });

  test('config helper appends missing plugin section', () {
    expect(
      enablePluginInConfig('[features]\nexample = true\n'),
      '[features]\nexample = true\n\n'
      '[plugins."checkpoint-autosave@personal"]\n'
      'enabled = true\n',
    );
  });
}
