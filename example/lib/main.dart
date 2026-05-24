// Dusk showroom: exercises every public dusk command surface. Each
// interactive widget on `/` is reachable via `dusk:snap` and acts as a
// target for the gesture and input handlers. Three named routes cover
// `dusk:navigate` and `dusk:navigate_back`; a dialog and bottom sheet
// cover `dusk:modal`; a network simulator covers
// `dusk:wait_for_network_idle`; a log+throw button covers
// `dusk:console` and `dusk:exceptions`.

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttersdk_dusk/dusk.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
  }
  runApp(const DuskShowroomApp());
}

class DuskShowroomApp extends StatelessWidget {
  const DuskShowroomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dusk Showroom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      initialRoute: '/',
      routes: {
        '/': (_) => const ShowroomHome(),
        '/details': (_) => const DetailsPage(),
        '/settings': (_) => const SettingsPage(),
      },
    );
  }
}

class ShowroomHome extends StatefulWidget {
  const ShowroomHome({super.key});
  @override
  State<ShowroomHome> createState() => _ShowroomHomeState();
}

class _ShowroomHomeState extends State<ShowroomHome> {
  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String _dropdown = 'alpha';
  bool _checked = false;
  bool _switched = false;
  int _counter = 0;
  String _lastKey = '';
  String _dragLabel = 'drop here';
  bool _networkBusy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _openDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('demo-dialog'),
        title: const Text('Demo dialog'),
        content: const Text('Hello from dialog'),
        actions: [
          TextButton(
            key: const Key('dialog-close'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 200,
        child: Center(
          child: TextButton(
            key: const Key('sheet-close'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close sheet'),
          ),
        ),
      ),
    );
  }

  Future<void> _simulateNetwork() async {
    setState(() => _networkBusy = true);
    developer.log('network: GET /api/items started', name: 'showroom');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    developer.log('network: GET /api/items 200 OK', name: 'showroom');
    if (mounted) setState(() => _networkBusy = false);
  }

  void _throwDemo() {
    developer.log('about to throw demo exception', name: 'showroom');
    throw StateError('Showroom demo exception (intentional)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dusk Showroom'),
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Open settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (e) {
          if (e is KeyDownEvent) {
            setState(() => _lastKey = e.logicalKey.keyLabel);
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Text input: type / clear / focus / blur / press_key'),
            TextField(
              key: const Key('name-field'),
              controller: _nameCtrl,
              focusNode: _nameFocus,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Last key: $_lastKey', key: const Key('last-key-label')),
            const SizedBox(height: 24),

            _section('Selection: set_checkbox / select_option'),
            DropdownButton<String>(
              key: const Key('mode-dropdown'),
              value: _dropdown,
              items: const [
                DropdownMenuItem(value: 'alpha', child: Text('Alpha')),
                DropdownMenuItem(value: 'beta', child: Text('Beta')),
                DropdownMenuItem(value: 'gamma', child: Text('Gamma')),
              ],
              onChanged: (v) => setState(() => _dropdown = v ?? 'alpha'),
            ),
            CheckboxListTile(
              key: const Key('agree-check'),
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: const Text('I agree'),
            ),
            SwitchListTile(
              key: const Key('notify-switch'),
              value: _switched,
              onChanged: (v) => setState(() => _switched = v),
              title: const Text('Notifications'),
            ),
            const SizedBox(height: 24),

            _section(
              'Clicks: tap / dblclick / triple_click / right_click / hover',
            ),
            ElevatedButton(
              key: const Key('inc-counter'),
              onPressed: () => setState(() => _counter++),
              child: Text('Counter: $_counter'),
            ),
            const SizedBox(height: 24),

            _section('Drag: drag'),
            Row(
              children: [
                Draggable<String>(
                  data: 'box-A',
                  feedback: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: 100,
                      height: 60,
                      alignment: Alignment.center,
                      color: Colors.teal.shade300,
                      child: const Text('source'),
                    ),
                  ),
                  child: Container(
                    key: const Key('drag-source'),
                    width: 100,
                    height: 60,
                    alignment: Alignment.center,
                    color: Colors.teal.shade100,
                    child: const Text('source'),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 16),
                DragTarget<String>(
                  onAcceptWithDetails: (d) =>
                      setState(() => _dragLabel = 'received: ${d.data}'),
                  builder: (_, _, _) => Container(
                    key: const Key('drag-target'),
                    width: 140,
                    height: 60,
                    alignment: Alignment.center,
                    color: Colors.amber.shade100,
                    child: Text(_dragLabel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _section('Modals: modal'),
            ElevatedButton(
              key: const Key('open-dialog'),
              onPressed: _openDialog,
              child: const Text('Open dialog'),
            ),
            ElevatedButton(
              key: const Key('open-sheet'),
              onPressed: _openSheet,
              child: const Text('Open bottom sheet'),
            ),
            const SizedBox(height: 24),

            _section('Navigation: navigate / navigate_back / get_routes'),
            ElevatedButton(
              key: const Key('go-details'),
              onPressed: () => Navigator.of(context).pushNamed('/details'),
              child: const Text('Go to details'),
            ),
            const SizedBox(height: 24),

            _section(
              'Diagnostics: console / exceptions / wait_for_network_idle',
            ),
            ElevatedButton(
              key: const Key('emit-log'),
              onPressed: () => developer.log(
                'showroom: hello from emit-log button',
                name: 'showroom',
              ),
              child: const Text('Emit log line'),
            ),
            ElevatedButton(
              key: const Key('throw-exception'),
              onPressed: _throwDemo,
              child: const Text('Throw demo exception'),
            ),
            ElevatedButton(
              key: const Key('start-network'),
              onPressed: _networkBusy ? null : _simulateNetwork,
              child: Text(_networkBusy ? 'Loading…' : 'Start fake request'),
            ),
            const SizedBox(height: 24),

            _section('Long list: scroll'),
            for (var i = 0; i < 30; i++)
              ListTile(key: Key('row-$i'), title: Text('Row $i')),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
    ),
  );
}

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: const Center(child: Text('Details page')),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings page')),
    );
  }
}
