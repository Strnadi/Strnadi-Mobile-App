/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */


import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strnadi/localization/translations.dart';

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
                Translations.text('aplikace_strnadi_je_momentalne_v_udrzbe'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2B18), // Hnědá
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                Translations.text('podrobnejsi_informace_najdete_zde'),
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
                  Translations.text('https_status_strnadi_cz_status_default'),
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