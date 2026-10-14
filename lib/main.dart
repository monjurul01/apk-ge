import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MetaHawaladarApp());
}

/// The studio is dark-only by design: a neutral near-black canvas is the
/// only honest background to judge generated colour against, so there is no
/// theme toggle to get wrong.
class MetaHawaladarApp extends StatelessWidget {
  const MetaHawaladarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meta Hawaladar Image Generator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}
