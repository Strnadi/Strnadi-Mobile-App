// Native-only visual QA harness: no backend, database, microphone or location.
// flutter run -t test/manual/native_controls_preview.dart -d <ios-simulator>
import 'package:flutter/material.dart';
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/components/native_ios_controls.dart';

void main() => runApp(const MaterialApp(home: NativeControlsPreview()));

class NativeControlsPreview extends StatefulWidget {
  const NativeControlsPreview({super.key});
  @override
  State<NativeControlsPreview> createState() => _NativeControlsPreviewState();
}

class _NativeControlsPreviewState extends State<NativeControlsPreview> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: Stack(
      children: [
        ListView.builder(
          itemCount: 30,
          itemBuilder: (_, row) => Container(
            height: 100,
            color: [
              const Color(0xFF9EBBAD),
              const Color(0xFFD8CC9C),
              const Color(0xFF659588),
            ][row % 3],
            alignment: Alignment.center,
            child: Text(
              'Native controls preview · ${row + 1}',
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        Positioned(
          top: 72,
          right: 20,
          child: GlassIconButton(
            nativeSymbol: 'xmark',
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () {},
          ),
        ),
        Positioned(
          top: 72,
          left: 20,
          child: GlassIconButton(
            nativeSymbol: 'bell',
            tooltip: 'Notifications',
            hasBadge: true,
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          ),
        ),
      ],
    ),
    bottomNavigationBar: NativeIOSTabBar(
      labels: const ['Map', 'Recordings', 'Record', 'Articles', 'Profile'],
      selectedIndex: index,
      onTap: (value) async {
        setState(() => index = value);
      },
    ),
  );
}
