import 'package:flutter/material.dart';
import 'recording/ios/recordingLiveActivity.dart';

class DebugMenuPage extends StatelessWidget {
  const DebugMenuPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Menu'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Option 1'),
              onTap: () {
                // TODO: Add debug action for Option 1
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('Option 2'),
              onTap: () {
                // TODO: Add debug action for Option 2
              },
            ),
            ListTile(
              leading: const Icon(Icons.live_tv),
              title: const Text('Live Activity Test'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LiveActivityTester()),
                );
              },
            ),
            // You can add more debug options here.
          ],
        ),
      ),
    );
  }
}