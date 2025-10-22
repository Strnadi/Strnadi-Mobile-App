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

class Language {
  final String name;
  final String code;
  final String flag;

  Language({required this.name, required this.code, required this.flag});
}

class CompactLanguageDropdown extends StatelessWidget {
  final List<Language> languages;
  final Language selectedLanguage;
  final ValueChanged<Language?> onChanged;

  const CompactLanguageDropdown({
    Key? key,
    required this.languages,
    required this.selectedLanguage,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButton<Language>(
        value: selectedLanguage,
        underline: const SizedBox(),
        icon: const Icon(Icons.arrow_drop_down, size: 20),
        items: languages.map((Language lang) {
          return DropdownMenuItem<Language>(
            value: lang,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lang.flag,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  lang.code.toUpperCase(),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
        selectedItemBuilder: (BuildContext context) {
          return languages.map((Language lang) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lang.flag,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 6),
                Text(
                  lang.code.toUpperCase(),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }
}
