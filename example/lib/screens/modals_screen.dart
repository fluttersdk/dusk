import 'package:flutter/material.dart';

/// Modal scenarios. Buttons open every Flutter-stock modal surface so
/// `dusk:dismiss_modals` (one tool, all modal kinds) can drive a clean
/// teardown regardless of which ones are open.
class ModalsScreen extends StatelessWidget {
  const ModalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modals')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.warning),
              label: const Text('Show Alert Dialog'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Alert Title'),
                  content: const Text('This is the alert body text.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.list),
              label: const Text('Show Simple Dialog'),
              onPressed: () => showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Choose Account'),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'work'),
                      child: const Text('Work'),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'personal'),
                      child: const Text('Personal'),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'archived'),
                      child: const Text('Archived'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.vertical_align_bottom),
              label: const Text('Show Bottom Sheet'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Bottom Sheet Title',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text('Bottom sheet body text goes here.'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close Sheet'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (ctx) => ElevatedButton.icon(
                icon: const Icon(Icons.info),
                label: const Text('Show Snackbar'),
                onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: const Text('This is the snackbar message.'),
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.fullscreen),
              label: const Text('Show Full Screen Dialog'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (ctx) => Scaffold(
                    appBar: AppBar(
                      title: const Text('Full Screen Dialog'),
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    body: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Full-screen modal route. dusk:dismiss_modals also '
                        'covers this kind via Navigator.maybePop.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
