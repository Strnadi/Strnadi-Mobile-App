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
