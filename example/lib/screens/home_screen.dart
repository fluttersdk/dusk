import 'package:flutter/material.dart';

/// Menu landing screen. Each tile pushes a named route so `dusk:navigate`
/// can drive cross-screen flows and `dusk:tap` can exercise the tile
/// taps directly.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const List<
    ({String route, String title, String subtitle, IconData icon})
  >
  _scenarios = [
    (
      route: '/buttons',
      title: 'Buttons',
      subtitle: 'tap / hover / drag — ElevatedButton, IconButton, InkWell, FAB',
      icon: Icons.touch_app,
    ),
    (
      route: '/inputs',
      title: 'Inputs',
      subtitle: 'type / select_option — TextField, Dropdown, Checkbox, Switch',
      icon: Icons.edit,
    ),
    (
      route: '/scroll',
      title: 'Scroll',
      subtitle: 'scroll — long ListView + horizontal scroll + sliver',
      icon: Icons.swap_vert,
    ),
    (
      route: '/modals',
      title: 'Modals',
      subtitle: 'dismiss_modals — Dialog, BottomSheet, SnackBar',
      icon: Icons.layers,
    ),
    (
      route: '/drawer',
      title: 'Drawer',
      subtitle: 'side drawer + end drawer + nested navigation',
      icon: Icons.menu,
    ),
    (
      route: '/forms',
      title: 'Forms',
      subtitle: 'wait / find — multi-field validation + async submit',
      icon: Icons.assignment,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dusk Example')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _scenarios.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = _scenarios[i];
          return ListTile(
            leading: Icon(s.icon),
            title: Text(s.title),
            subtitle: Text(s.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, s.route),
          );
        },
      ),
    );
  }
}
