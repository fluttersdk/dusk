import 'dart:async';

import 'package:flutter/material.dart';

/// Wait / find scenarios. Async submit drives a 2-second processing
/// state then either a Success banner or Error banner — perfect target
/// for `dusk:wait_for text='Form submitted successfully'` plus a
/// `dusk:find text='Email is required'` validation probe before submit.
class FormsScreen extends StatefulWidget {
  const FormsScreen({super.key});

  @override
  State<FormsScreen> createState() => _FormsScreenState();
}

class _FormsScreenState extends State<FormsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _submitting = false;
  String? _resultBanner;
  bool _shouldFail = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _submitting = true;
      _resultBanner = null;
    });
    await Future<void>.delayed(const Duration(seconds: 2));
    setState(() {
      _submitting = false;
      _resultBanner = _shouldFail
          ? 'Submission failed: server returned 500'
          : 'Form submitted successfully';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forms')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!v.contains('@')) {
                    return 'Email must contain @';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.length < 10)
                    ? 'Message must be at least 10 characters'
                    : null,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Simulate Server Error'),
                value: _shouldFail,
                onChanged: (v) => setState(() => _shouldFail = v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting...' : 'Submit'),
              ),
              const SizedBox(height: 16),
              if (_resultBanner != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _shouldFail
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _shouldFail ? Icons.error_outline : Icons.check_circle,
                        color: _shouldFail ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_resultBanner!)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
