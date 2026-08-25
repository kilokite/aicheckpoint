import 'package:flutter/material.dart';

import '../models/receipt_printer_settings.dart';

class ReceiptPrinterSettingsDialog extends StatefulWidget {
  const ReceiptPrinterSettingsDialog({
    super.key,
    required this.initialSettings,
  });

  final ReceiptPrinterSettings initialSettings;

  @override
  State<ReceiptPrinterSettingsDialog> createState() =>
      _ReceiptPrinterSettingsDialogState();
}

class _ReceiptPrinterSettingsDialogState
    extends State<ReceiptPrinterSettingsDialog> {
  late bool _enabled;
  late final TextEditingController _urlController;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialSettings.enabled;
    _urlController = TextEditingController(
      text: widget.initialSettings.webhookUrl,
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _save() {
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      setState(() => _urlError = '请输入有效的 HTTP 或 HTTPS 地址');
      return;
    }
    Navigator.pop(
      context,
      ReceiptPrinterSettings(enabled: _enabled, webhookUrl: url),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.receipt_long_outlined),
    title: const Text('小票机设置'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('创建快照后打印小票'),
            subtitle: const Text('支持手动创建和 Coding Agent 自动快照'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('receipt-webhook-url'),
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Webhook 地址',
              hintText: ReceiptPrinterSettings.defaultWebhookUrl,
              helperText: '默认连接本机 print-service',
              errorText: _urlError,
            ),
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
