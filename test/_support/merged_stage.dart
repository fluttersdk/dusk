import 'package:flutter/material.dart';

/// The widget tree of fluttersdk/dusk#60: a `MergeSemantics` stage whose own
/// tap handler fills the frame, with a small labelled `Skip intro` button in
/// the bottom-right corner. The merged node's centre belongs to the stage, not
/// to the button.
class MergedStage extends StatelessWidget {
  const MergedStage({
    super.key,
    required this.onStageTap,
    required this.onSkip,
  });

  final VoidCallback onStageTap;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: GestureDetector(
        onTap: onStageTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Color(0xFF000000)),
            Positioned(
              right: 24,
              bottom: 24,
              child: Semantics(
                button: true,
                label: 'Skip intro',
                onTap: onSkip,
                // Opaque: an empty SizedBox has no hit surface of its own, so a
                // pointer would fall through to the stage.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSkip,
                  child: const SizedBox(width: 120, height: 40),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [MergedStage] inside an app shell, filling the test view.
Widget mergedStageApp({
  required VoidCallback onStageTap,
  required VoidCallback onSkip,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MergedStage(onStageTap: onStageTap, onSkip: onSkip),
    ),
  );
}

/// A merged boundary with two labelled buttons and a tap handler of its own,
/// neither button at the centre: there is no single control to move a tap to.
Widget mergedChoiceApp({
  required VoidCallback onStageTap,
  required VoidCallback onYes,
  required VoidCallback onNo,
}) {
  Widget choice(String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(width: 80, height: 40),
      ),
    );
  }

  return MaterialApp(
    home: Scaffold(
      body: MergeSemantics(
        child: GestureDetector(
          onTap: onStageTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const ColoredBox(color: Color(0xFF000000)),
              Positioned(left: 24, bottom: 24, child: choice('Yes', onYes)),
              Positioned(right: 24, bottom: 24, child: choice('No', onNo)),
            ],
          ),
        ),
      ),
    ),
  );
}
