import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

/// Welcome screen for the fluttersdk_dusk Magic-stack example.
///
/// Uses W-prefix Wind widgets (WDiv, WText, WButton) so that
/// WindDuskIntegration produces 6-field className enrichment on every
/// snapshotted ref (breakpoint, brightness, platform, states, bgColor,
/// textColor).
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fluttersdk_dusk — Magic example')),
      body: WDiv(
        className:
            'flex flex-col items-center justify-center w-full h-full bg-white dark:bg-gray-900',
        children: [
          WDiv(
            className:
                'flex flex-col items-center gap-6 p-8 rounded-2xl bg-gray-50 dark:bg-gray-800 shadow-lg max-w-sm',
            children: [
              WText(
                'Dusk Magic Example',
                className: 'text-2xl font-bold text-gray-900 dark:text-white',
              ),
              WText(
                'Wind UI widgets are enriched with 6-field className metadata '
                'when this screen is captured via `dusk:snap`.',
                className:
                    'text-sm text-gray-600 dark:text-gray-400 text-center',
              ),
              WButton(
                className:
                    'bg-indigo-600 dark:bg-indigo-500 text-white px-6 py-3 rounded-xl font-semibold',
                onTap: () => Magic.snackbar(
                  'dusk',
                  'WindDuskIntegration enriched this tap. Run dusk:snap to capture.',
                ),
                child: const Text('Trigger Snackbar'),
              ),
              WButton(
                className:
                    'bg-gray-200 dark:bg-gray-700 text-gray-900 dark:text-white px-6 py-3 rounded-xl font-semibold',
                onTap: () => Log.info(
                  'dusk example: button pressed at ${DateTime.now()}',
                ),
                child: const Text('Emit Log'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
