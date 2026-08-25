import 'package:flutter/material.dart';

class SnapshotTitleDialog extends StatefulWidget {
  const SnapshotTitleDialog({
    super.key,
    required this.title,
    required this.fieldLabel,
    required this.confirmLabel,
    this.initialValue = '',
    this.hintText,
    this.allowEmpty = true,
  });

  final String title;
  final String fieldLabel;
  final String confirmLabel;
  final String initialValue;
  final String? hintText;
  final bool allowEmpty;

  @override
  State<SnapshotTitleDialog> createState() => _SnapshotTitleDialogState();
}

class _SnapshotTitleDialogState extends State<SnapshotTitleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!widget.allowEmpty && value.isEmpty) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const Key('snapshot-title-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: widget.fieldLabel,
          hintText: widget.hintText,
        ),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
