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
/*
 * recListItem.dart
 */

import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/database/databaseNew.dart';

class EditRecordingPage extends StatefulWidget {
  final Recording recording;

  const EditRecordingPage({Key? key, required this.recording}) : super(key: key);

  @override
  _EditRecordingPageState createState() => _EditRecordingPageState();
}

class _EditRecordingPageState extends State<EditRecordingPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _countController;
  late final TextEditingController _deviceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recording.name ?? '');
    _noteController = TextEditingController(text: widget.recording.note ?? '');
    _countController = TextEditingController(
        text: widget.recording.estimatedBirdsCount?.toString() ?? '');
    _deviceController = TextEditingController(text: widget.recording.device ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _countController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Update fields from the form
    widget.recording.name = _nameController.text.trim();
    widget.recording.note = _noteController.text.trim();
    widget.recording.estimatedBirdsCount =
        int.tryParse(_countController.text) ??
            widget.recording.estimatedBirdsCount;
    widget.recording.device = _deviceController.text.trim();

    // Persist the change
    await DatabaseNew.updateRecording(widget.recording);
    // If the recording already exists on the backend, patch it there as well
    if (widget.recording.BEId != null) {
      try {
        await DatabaseNew.updateRecordingBE(widget.recording);
      } catch (e, stackTrace) {
        logger.e('Error updating recording', error: e, stackTrace: stackTrace);
        // Ignore backend sync errors for now; user changes are saved locally
      }
    }

    // Return the updated object to the caller
    if (mounted) {
      Navigator.pop(context, widget.recording);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Upravit záznam')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Název'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Poznámka'),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _countController,
                decoration: const InputDecoration(labelText: 'Počet strnadů'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _deviceController,
                decoration: const InputDecoration(labelText: 'Zařízení'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _save,
                child: Text(t('Uložit změny')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}