import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/receipt_printer_settings.dart';

class ReceiptPrinterSettingsStore {
  ReceiptPrinterSettingsStore({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  Future<File> get _file async {
    final support = _directory ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Checkpoint'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'settings.json'));
  }

  Future<ReceiptPrinterSettings> load() async {
    final file = await _file;
    if (!await file.exists()) return const ReceiptPrinterSettings();

    try {
      final decoded = jsonDecode(await file.readAsString());
      return ReceiptPrinterSettings.fromJson(decoded as Map<String, dynamic>);
    } on Object {
      await file.copy('${file.path}.invalid');
      return const ReceiptPrinterSettings();
    }
  }

  Future<void> save(ReceiptPrinterSettings settings) async {
    final file = await _file;
    final temp = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await temp.writeAsString(encoder.convert(settings.toJson()));
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
