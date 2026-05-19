import 'package:flutter/material.dart';

/// Drawer + endDrawer scenarios. The AppBar leading icon opens the side
/// drawer, the trailing icon opens the end drawer. Both contain a stack
/// of identifiable destinations for `dusk:tap` to drive.
class DrawerScreen extends StatefulWidget {
  const DrawerScreen({super.key});

  @override
  State<DrawerScreen> createState() => _DrawerScreenState();
}

class _DrawerScreenState extends State<DrawerScreen> {
  String _selectedDestination = 'Inbox';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawer'),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Open End Drawer',
              icon: const Icon(Icons.settings),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: _destinationIndex(),
        onDestinationSelected: (i) {
          setState(() {
            _selectedDestination = _destinations[i];
          });
          Navigator.pop(context);
        },
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Mailbox', style: TextStyle(fontSize: 18)),
          ),
          for (final name in _destinations)
            NavigationDrawerDestination(
              icon: Icon(_iconFor(name)),
              label: Text(name),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Other'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          children: const [
            DrawerHeader(child: Text('Settings')),
            ListTile(
              leading: Icon(Icons.dark_mode),
              title: Text('Theme'),
              subtitle: Text('System'),
            ),
            ListTile(
              leading: Icon(Icons.language),
              title: Text('Language'),
              subtitle: Text('Türkçe'),
            ),
            ListTile(
              leading: Icon(Icons.notifications),
              title: Text('Notifications'),
              subtitle: Text('Enabled'),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.bug_report),
              title: Text('Send Feedback'),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(_selectedDestination), size: 64),
              const SizedBox(height: 16),
              Text(
                'Selected: $_selectedDestination',
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open the side drawer (top-left icon) to switch destinations, '
                'or the end drawer (top-right icon) for settings.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _destinations = [
    'Inbox',
    'Starred',
    'Sent',
    'Drafts',
    'Trash',
  ];

  int _destinationIndex() {
    final i = _destinations.indexOf(_selectedDestination);
    return i < 0 ? 0 : i;
  }

  IconData _iconFor(String dest) {
    switch (dest) {
      case 'Inbox':
        return Icons.inbox;
      case 'Starred':
        return Icons.star;
      case 'Sent':
        return Icons.send;
      case 'Drafts':
        return Icons.edit_note;
      case 'Trash':
        return Icons.delete;
      default:
        return Icons.folder;
    }
  }
}
