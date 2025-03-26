import 'package:flutter/material.dart';

class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Osobní údaje'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {}, // Save action
            child: const Text('Uložit', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTextField('Jméno', 'Lenka'),
            _buildTextField('Příjmení', 'Nováková'),
            _buildTextField('Přezdívka', 'novolenka'),
            _buildTextField('E-mail', 'email@example.com'),
            _buildTextField('PSČ', '530 09'),
            ListTile(
              title: const Text('Kraj'),
              subtitle: const Text('Pardubický'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}, // Open region selection
            ),
            const Divider(),
            ListTile(
              title: const Text('Změna hesla'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}, // Open password change
            ),
            ListTile(
              title: const Text('Chci si smazat účet', style: TextStyle(color: Colors.red)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}, // Open delete account confirmation
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        ),
        controller: TextEditingController(text: value),
      ),
    );
  }
}
