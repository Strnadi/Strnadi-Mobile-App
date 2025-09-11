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
import 'package:strnadi/localization/translations.dart';

class ResetEmailSent extends StatelessWidget {
  final String userEmail;

  const ResetEmailSent({Key? key, required this.userEmail}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color yellowishBlack = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    return Scaffold(
      backgroundColor: Colors.white,
      // If you want an AppBar, uncomment the lines below
      // appBar: AppBar(
      //   backgroundColor: Colors.white,
      //   elevation: 0,
      //   leading: IconButton(
      //     icon: Image.asset('assets/icons/backButton.png', width: 30, height: 30),
      //     onPressed: () => Navigator.pop(context),
      //   ),
      // ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            // This layout places the text at the top and button at bottom
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              const Text(
                Translations.text('e_mail_poslan'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Právě jsme odeslali e-mail na $userEmail.\n'
                    'Doručení může trvat až 10 minut.\n\n'
                    'Pokud brzy neobdržíte pokyny, zkontrolujte složku '
                    'se spamem nebo nevyžádanou poštou.\n\n'
                    'Pokud ani to nepomůže, zkuste odeslat žádost znovu.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              // Add more spacing so the button stays at the bottom
              const Spacer(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // or navigate to another screen if preferred
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor: Colors.transparent,
              backgroundColor: yellow,
              foregroundColor: yellowishBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: Text(Translations.text('ok_1')),
          ),
        ),
      ),
    );
  }
}