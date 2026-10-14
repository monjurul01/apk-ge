import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiImageStudioApp());
}

/// The studio is dark-only by design: a neutral near-black canvas is the
/// only honest background to judge generated colour against, so there is no
/// theme toggle to get wrong.
class AiImageStudioApp extends StatelessWidget {
  const AiImageStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Image Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
