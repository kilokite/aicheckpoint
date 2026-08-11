import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

export 'app.dart' show CheckpointApp;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(900, 560),
    center: true,
    title: 'Checkpoint',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  final argumentPath = arguments
      .where((item) => !item.startsWith('-'))
      .firstOrNull;
  runApp(
    CheckpointApp(
      initialPath: argumentPath ?? Directory.current.path,
      silentInitialFailure: argumentPath == null,
    ),
  );
}
