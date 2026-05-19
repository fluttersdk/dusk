import 'package:flutter/material.dart';

/// Type / select_option / press_key scenarios. Every input declares a
/// distinct label so `dusk:find text='Email'` resolves the field and
/// `dusk:type ref text='...'` lands typed characters on it.
class InputsScreen extends StatefulWidget {
  const InputsScreen({super.key});

  @override
  State<InputsScreen> createState() => _InputsScreenState();
}

class _InputsScreenState extends State<InputsScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String _country = 'Türkiye';
  bool _terms = false;
  bool _notifications = true;
  double _volume = 50;

  static const List<String> _countries = [
    'Türkiye',
    'Almanya',
    'İngiltere',
    'ABD',
    'Japonya',
  ];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inputs')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'user@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Bio',
                hintText: 'Multi-line input for press_key tests',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Bare DropdownButton without InputDecorator + HideUnderline
            // wrapping so the Semantics ref resolves directly to the
            // DropdownButton element (ext.dusk.select_option walks the
            // resolved widget by runtimeType match).
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Text('Country', style: TextStyle(fontSize: 12)),
            ),
            DropdownButton<String>(
              value: _country,
              isExpanded: true,
              items: _countries
                  .map(
                    (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _country = v);
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Accept Terms'),
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
            ),
            SwitchListTile(
              title: const Text('Enable Notifications'),
              value: _notifications,
              onChanged: (v) => setState(() => _notifications = v),
            ),
            const SizedBox(height: 8),
            Text('Volume: ${_volume.toInt()}'),
            Slider(
              value: _volume,
              max: 100,
              divisions: 10,
              label: _volume.toInt().toString(),
              onChanged: (v) => setState(() => _volume = v),
            ),
            const SizedBox(height: 16),
            // Echo block — every value is mirrored as plain Text so the
            // snapshot reader can verify the input wiring end-to-end via
            // a single `dusk:snap` capture.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email echo: ${_emailCtrl.text}'),
                  Text('Bio echo: ${_bioCtrl.text}'),
                  Text('Country echo: $_country'),
                  Text('Terms accepted: $_terms'),
                  Text('Notifications on: $_notifications'),
                  Text('Volume value: ${_volume.toInt()}'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // The echo above is computed at build time; React the user
            // can force a rebuild via this button if the controller's
            // own onChanged path is not yet wired in their fork.
            ElevatedButton(
              onPressed: () => setState(() {}),
              child: const Text('Refresh Echo'),
            ),
          ],
        ),
      ),
    );
  }
}
