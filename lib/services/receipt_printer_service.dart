import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/snapshot.dart';

class ReceiptPrinterException implements Exception {
  const ReceiptPrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptPrinterService {
  static const String _logoAssetPath = 'assets/checkpoint_receipt_logo.png';

  ReceiptPrinterService({HttpClient? client})
    : _client = client ?? HttpClient(),
      _ownsClient = client == null;

  final HttpClient _client;
  final bool _ownsClient;

  Future<void> printSnapshot(Snapshot snapshot, String webhookUrl) async {
    final uri = Uri.tryParse(webhookUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const ReceiptPrinterException('小票机 Webhook 地址无效');
    }

    try {
      final request = await _client
          .postUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(_buildPayload(snapshot)));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ReceiptPrinterException(
          '小票机返回 HTTP ${response.statusCode}'
          '${body.trim().isEmpty ? '' : '：${body.trim()}'}',
        );
      }
    } on ReceiptPrinterException {
      rethrow;
    } on Object catch (error) {
      throw ReceiptPrinterException('无法连接小票机：$error');
    }
  }

  Map<String, dynamic> _buildPayload(Snapshot snapshot) {
    final localTime = snapshot.createdAt.toLocal();
    final time =
        '${localTime.year.toString().padLeft(4, '0')}-'
        '${localTime.month.toString().padLeft(2, '0')}-'
        '${localTime.day.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}:'
        '${localTime.second.toString().padLeft(2, '0')}';
    final shortHash = snapshot.commitHash.length > 12
        ? snapshot.commitHash.substring(0, 12)
        : snapshot.commitHash;
    final logoPath = p.joinAll([
      File(Platform.resolvedExecutable).parent.path,
      'data',
      'flutter_assets',
      ...p.split(_logoAssetPath),
    ]);

    return {
      'id': 'checkpoint-${snapshot.id}',
      'options': {'encoding': 'GB18030', 'width': 64, 'lineSpace': 20},
      'commands': [
        {'op': 'font', 'value': 'b'},
        {
          'op': 'text',
          'text': snapshot.title,
          'align': 'lt',
          'font': 'a',
          'style': 'b',
          'size': [0, 0],
        },
        {'op': 'font', 'value': 'b'},
        {'op': 'style', 'value': 'normal'},
        {'op': 'align', 'value': 'lt'},
        {'op': 'line', 'char': '-'},
        {
          'op': 'field',
          'label': '项目',
          'value': p.basename(snapshot.repositoryPath),
          'labelCols': 6,
        },
        {
          'op': 'field',
          'label': '分支',
          'value': snapshot.branch,
          'labelCols': 6,
        },
        {
          'op': 'field',
          'label': '文件',
          'value': '${snapshot.fileCount}',
          'labelCols': 6,
        },
        {
          'op': 'field',
          'label': '变更',
          'value': '+${snapshot.insertions}  -${snapshot.deletions}',
          'labelCols': 6,
        },
        {'op': 'field', 'label': '哈希', 'value': shortHash, 'labelCols': 6},
        {'op': 'field', 'label': '时间', 'value': time, 'labelCols': 6},
        {'op': 'line', 'char': '-'},
        {'op': 'feed', 'n': 1},
        {
          'op': 'image',
          'src': logoPath,
          'dither': false,
          'threshold': 128,
          'maxWidth': 300,
          'align': 'ct',
        },
        {'op': 'cut', 'partial': true},
      ],
    };
  }

  void close() {
    if (_ownsClient) _client.close(force: true);
  }
}
