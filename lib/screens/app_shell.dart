import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/generation.dart';
import 'batch_screen.dart';
import 'dola_tab_screen.dart';
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

  /// The Dola tab loads a real page, so it is not built until it is first
  /// opened. Otherwise every launch would fetch the site whether or not the
  /// user went anywhere near that tab.
  bool _dolaOpened = false;

  @override
  void dispose() {
    _gallery.dispose();
    super.dispose();
  }

  static const _destinations = [
    (icon: Icons.auto_awesome_outlined, selected: Icons.auto_awesome, label: 'Studio'),
    (icon: Icons.layers_outlined, selected: Icons.layers, label: 'Batch'),
    (icon: Icons.public_outlined, selected: Icons.public, label: 'Dola'),
    (icon: Icons.grid_view_outlined, selected: Icons.grid_view, label: 'Gallery'),
    (icon: Icons.tune_outlined, selected: Icons.tune, label: 'Settings'),
  ];

  /// An IndexedStack rather than a switch: the Dola tab hosts a live page,
  /// and rebuilding the subtree on every tab change would reload it and lose
  /// whatever conversation was in progress. The other tabs keep their state
  /// for free, which is also what the previous switch already implied by
  /// holding the gallery above them.
  Widget _page() {
    return IndexedStack(
      index: _index,
      children: [
        StudioScreen(gallery: _gallery),
        BatchScreen(gallery: _gallery),
        _dolaOpened
            ? DolaTabScreen(gallery: _gallery)
            : const SizedBox.shrink(),
        GalleryScreen(gallery: _gallery),
        const SettingsScreen(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);

    return Scaffold(
      backgroundColor: Skin.canvas,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _rail(),
                  const VerticalDivider(width: 1, color: Skin.line),
                  Expanded(child: _page()),
                ],
              )
            : _page(),
      ),
      bottomNavigationBar: wide
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Skin.line)),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
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

  void _select(int i) {
    setState(() {
      _index = i;
      if (i == 2) _dolaOpened = true;
    });
  }

  Widget _rail() {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          const SizedBox(height: Skin.s5),
          // Wordmark: the MH mark, the only branding in the app.
          ClipRRect(
            borderRadius: BorderRadius.circular(Skin.rSm),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 30,
              height: 30,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: Skin.s5),
          Expanded(
            child: NavigationRail(
              backgroundColor: Skin.canvas,
              selectedIndex: _index,
              onDestinationSelected: _select,
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
              padding: const EdgeInsets.only(bottom: Skin.s4),
              child: Text(
                '${_gallery.length}',
                style: const TextStyle(color: Skin.textFaint, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
