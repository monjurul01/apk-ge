import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/generation.dart';
import 'batch_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import 'studio_screen.dart';

/// Results produced during this run, shared by the Studio, Batch and
/// Gallery tabs. Kept in memory on purpose: generated images can be tens of
/// megabytes and the user decides what is worth writing to disk.
class SessionGallery extends ChangeNotifier {
  final List<GenerationResult> _items = [];

  List<GenerationResult> get items => List.unmodifiable(_items);

  int get length => _items.length;

  void add(GenerationResult r) {
    _items.insert(0, r);
    notifyListeners();
  }

  void addAll(Iterable<GenerationResult> rs) {
    _items.insertAll(0, rs);
    notifyListeners();
  }

  void remove(GenerationResult r) {
    _items.remove(r);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

/// Top-level navigation.
///
/// Replaces the previous AppBar + push-a-new-route structure with a
/// persistent rail on desktop and a bottom bar on phones, so switching
/// between composing, queueing and reviewing never loses state.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _gallery = SessionGallery();
  int _index = 0;

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  static const _destinations = [
    (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Studio'),
    (icon: Icons.layers_outlined, selected: Icons.layers, label: 'Batch'),
    (icon: Icons.grid_view_outlined, selected: Icons.grid_view, label: 'Gallery'),
    (icon: Icons.tune_outlined, selected: Icons.tune, label: 'Settings'),
  ];

  Widget _page() {
    return switch (_index) {
      0 => StudioScreen(gallery: _gallery),
      1 => BatchScreen(gallery: _gallery),
      2 => GalleryScreen(gallery: _gallery),
      _ => const SettingsScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);

    return Scaffold(
      backgroundColor: Ink.canvas,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _rail(),
                  const VerticalDivider(width: 1, color: Ink.line),
                  Expanded(child: _page()),
                ],
              )
            : _page(),
      ),
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Ink.line)),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: d.label,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _rail() {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          const SizedBox(height: Ink.s5),
          // Wordmark: a single amber square, the only branding in the app.
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Ink.accent,
              borderRadius: BorderRadius.circular(Ink.rSm),
            ),
            child: const Icon(Icons.circle, size: 9, color: Ink.onAccent),
          ),
          const SizedBox(height: Ink.s5),
          Expanded(
            child: NavigationRail(
              backgroundColor: Ink.canvas,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _gallery,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(bottom: Ink.s4),
              child: Text(
                '${_gallery.length}',
                style: const TextStyle(color: Ink.textFaint, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
