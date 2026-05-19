import 'package:flutter/material.dart';

/// Tap / hover / drag scenarios. Every interactive widget has a stable
/// semantic label so `dusk:find text='Click Me'` resolves cleanly and
/// `dusk:tap` lands the synthesised pointer event on the right surface.
class ButtonsScreen extends StatefulWidget {
  const ButtonsScreen({super.key});

  @override
  State<ButtonsScreen> createState() => _ButtonsScreenState();
}

class _ButtonsScreenState extends State<ButtonsScreen> {
  int _tapCount = 0;
  int _longPressCount = 0;
  bool _disabledButtonTapped = false;
  Offset _draggablePosition = const Offset(40, 40);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buttons')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Taps: $_tapCount   Long presses: $_longPressCount',
              key: const Key('counters'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _tapCount++),
              child: const Text('Elevated Button'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => setState(() => _tapCount++),
              child: const Text('Outlined Button'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _tapCount++),
              child: const Text('Text Button'),
            ),
            const SizedBox(height: 8),
            const ElevatedButton(
              onPressed: null,
              child: Text('Disabled Button'),
            ),
            const SizedBox(height: 8),
            // Off-viewport target (the actionability gate must FAIL).
            Transform.translate(
              offset: const Offset(2000, 0),
              child: ElevatedButton(
                onPressed: () => setState(() => _disabledButtonTapped = true),
                child: const Text('Offscreen Button'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Like',
                  onPressed: () => setState(() => _tapCount++),
                  icon: const Icon(Icons.favorite),
                ),
                IconButton(
                  tooltip: 'Share',
                  onPressed: () => setState(() => _tapCount++),
                  icon: const Icon(Icons.share),
                ),
                IconButton(
                  tooltip: 'Bookmark',
                  onPressed: () => setState(() => _tapCount++),
                  icon: const Icon(Icons.bookmark),
                ),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => setState(() => _tapCount++),
              onLongPress: () => setState(() => _longPressCount++),
              child: Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Long Press Area'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Drop Target'),
                      ),
                    ),
                  ),
                  Positioned(
                    left: _draggablePosition.dx,
                    top: _draggablePosition.dy,
                    child: Draggable(
                      feedback: const _DragChip(label: 'Dragging'),
                      childWhenDragging: const _DragChip(label: 'Empty'),
                      onDragEnd: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        setState(() {
                          _draggablePosition = box.globalToLocal(
                            details.offset,
                          );
                        });
                      },
                      child: const _DragChip(label: 'Drag Me'),
                    ),
                  ),
                ],
              ),
            ),
            if (_disabledButtonTapped)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Offscreen button tapped — gate should have blocked this',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _tapCount++),
        icon: const Icon(Icons.add),
        label: const Text('Increment'),
      ),
    );
  }
}

class _DragChip extends StatelessWidget {
  const _DragChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
