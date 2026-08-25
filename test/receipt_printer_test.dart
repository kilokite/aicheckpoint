import 'dart:convert';
import 'dart:io';

import 'package:checkpoint/models/receipt_printer_settings.dart';
import 'package:checkpoint/models/snapshot.dart';
import 'package:checkpoint/services/receipt_printer_service.dart';
import 'package:checkpoint/services/receipt_printer_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists receipt printer settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'checkpoint_printer_settings_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = ReceiptPrinterSettingsStore(directory: directory);

    final defaults = await store.load();
    expect(defaults.enabled, isFalse);
    expect(defaults.webhookUrl, ReceiptPrinterSettings.defaultWebhookUrl);

    const changed = ReceiptPrinterSettings(
      enabled: true,
      webhookUrl: 'http://192.168.1.8:9101/print',
    );
    await store.save(changed);
    final loaded = await store.load();
    expect(loaded.enabled, isTrue);
    expect(loaded.webhookUrl, changed.webhookUrl);
  });

  test('posts a checkpoint receipt to the configured webhook', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? received;
    server.listen((request) async {
      received =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response.statusCode = HttpStatus.accepted;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":true}');
      await request.response.close();
    });

    final service = ReceiptPrinterService();
    addTearDown(service.close);
    await service.printSnapshot(
      _snapshot,
      'http://127.0.0.1:${server.port}/print',
    );

    expect(received?['id'], 'checkpoint-snapshot-id');
    expect(received?['options'], {
      'encoding': 'GB18030',
      'width': 64,
      'lineSpace': 20,
    });
    final commands = received?['commands'] as List<dynamic>;
    expect(commands.first, {'op': 'font', 'value': 'b'});
    expect(commands[1], {
      'op': 'text',
      'text': '自动保存设置面板',
      'align': 'lt',
      'font': 'a',
      'style': 'b',
      'size': [0, 0],
    });
    expect(
      commands.whereType<Map<String, dynamic>>().every(
        (command) => command['op'] != 'text' || command['align'] == 'lt',
      ),
      isTrue,
    );
    final logo = commands.whereType<Map<String, dynamic>>().singleWhere(
      (command) => command['op'] == 'image',
    );
    expect(
      (logo['src'] as String).replaceAll('\\', '/'),
      endsWith('/data/flutter_assets/assets/checkpoint_receipt_logo.png'),
    );
    expect(logo, containsPair('align', 'ct'));
    expect((commands.last as Map<String, dynamic>)['op'], 'cut');
  });

  test('rejects an invalid webhook URL before sending', () async {
    final service = ReceiptPrinterService();
    addTearDown(service.close);
    await expectLater(
      service.printSnapshot(_snapshot, 'not-a-webhook'),
      throwsA(isA<ReceiptPrinterException>()),
    );
  });
}

final _snapshot = Snapshot(
  id: 'snapshot-id',
  repositoryPath: r'C:\workspace\checkpoint',
  commitHash: '1234567890abcdef',
  indexTreeHash: 'index',
  baseHash: 'base',
  branch: 'main',
  title: '自动保存设置面板',
  createdAt: DateTime(2026, 8, 25, 18, 30),
  fileCount: 4,
  insertions: 32,
  deletions: 7,
);
