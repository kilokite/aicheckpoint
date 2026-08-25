class ReceiptPrinterSettings {
  const ReceiptPrinterSettings({
    this.enabled = false,
    this.webhookUrl = defaultWebhookUrl,
  });

  static const String defaultWebhookUrl = 'http://127.0.0.1:9101/print';

  final bool enabled;
  final String webhookUrl;

  ReceiptPrinterSettings copyWith({bool? enabled, String? webhookUrl}) =>
      ReceiptPrinterSettings(
        enabled: enabled ?? this.enabled,
        webhookUrl: webhookUrl ?? this.webhookUrl,
      );

  factory ReceiptPrinterSettings.fromJson(Map<String, dynamic> json) =>
      ReceiptPrinterSettings(
        enabled: json['enabled'] as bool? ?? false,
        webhookUrl: (json['webhookUrl'] as String?)?.trim().isNotEmpty == true
            ? (json['webhookUrl'] as String).trim()
            : defaultWebhookUrl,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'webhookUrl': webhookUrl,
  };
}
