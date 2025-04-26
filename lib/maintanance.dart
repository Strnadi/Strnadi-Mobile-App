

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({Key? key}) : super(key: key);

  static const String _statusUrl = 'https://status.strnadi.cz/status/default';

  Future<void> _openStatusPage() async {
    final Uri url = Uri.parse(_statusUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFD641), // Strnadí žlutá
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/WIP.png',
                width: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),
              const Text(
                'Aplikace Strnadi je momentálně v údržbě.',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2B18), // Hnědá
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Podrobnější informace najdete zde:',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2D2B18),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _openStatusPage,
                child: const Text(
                  'https://status.strnadi.cz/status/default',
                  style: TextStyle(
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                    color: Color(0xFF2D2B18),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}