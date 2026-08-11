import 'package:flutter/material.dart';

import 'pages/checkpoint_home.dart';

class CheckpointApp extends StatelessWidget {
  const CheckpointApp({
    super.key,
    this.initialPath,
    this.silentInitialFailure = false,
    this.enableMcp = true,
  });

  final String? initialPath;
  final bool silentInitialFailure;
  final bool enableMcp;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF16855B);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: const Color(0xFFF7F7F5),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Checkpoint',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F7F5),
        fontFamily: 'Microsoft YaHei UI',
        dividerColor: const Color(0xFFE3E3DE),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        dialogTheme: const DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 450),
        ),
      ),
      home: CheckpointHome(
        initialPath: initialPath,
        silentInitialFailure: silentInitialFailure,
        enableMcp: enableMcp,
      ),
    );
  }
}
