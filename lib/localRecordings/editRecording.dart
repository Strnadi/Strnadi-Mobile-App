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
import 'package:flutter/material.dart';
import 'package:strnadi/database/databaseNew.dart';

import 'package:strnadi/database/Models/recording.dart';

class EditRecordingPage extends StatefulWidget {
  final Recording recording;

  const EditRecordingPage({Key? key, required this.recording})
      : super(key: key);

  @override
  _EditRecordingPageState createState() => _EditRecordingPageState();
}

class _EditRecordingPageState extends State<EditRecordingPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late double _strnadiCountController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recording.name ?? '');
    _noteController = TextEditingController(text: widget.recording.note ?? '');
    _strnadiCountController =
        widget.recording.estimatedBirdsCount.clamp(1, 3).toDouble();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final int? recordingId = widget.recording.id;
    if (recordingId == null || recordingId <= 0) {
      _showSaveMessage('editRecording.messages.saveFailed');
      return;
    }

    final String stagedName = _nameController.text.trim();
    final String stagedNote = _noteController.text.trim();
    final int stagedBirdCount = _strnadiCountController.toInt();

    FocusScope.of(context).unfocus();
    setState(() {
      _isSaving = true;
    });

    try {
      final Recording? latest =
          await DatabaseNew.getRecordingFromDbByIdNoMail(recordingId);
      if (latest == null) {
        throw StateError('The recording no longer exists.');
      }

      latest
        ..name = stagedName
        ..note = stagedNote
        ..estimatedBirdsCount = stagedBirdCount;

      // Persist staged values before mutating the object shared with the
      // previous page. An active upload lease makes this update fail closed.
      await DatabaseNew.updateRecording(latest);

      widget.recording
        ..name = stagedName
        ..note = stagedNote
        ..estimatedBirdsCount = stagedBirdCount;

      // Re-read upload-owned fields. The backend parent may have been created
      // after this edit page opened.
      final Recording updated =
          await DatabaseNew.getRecordingFromDbByIdNoMail(recordingId) ?? latest;
      if (updated.BEId != null) {
        await DatabaseNew.updateRecordingBE(updated);
      }

      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e, stackTrace) {
      logger.e(
        'Error saving recording metadata',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;

      Recording? persisted;
      try {
        persisted = await DatabaseNew.getRecordingFromDbByIdNoMail(recordingId);
      } catch (readError, readStackTrace) {
        logger.e(
          'Error checking whether recording metadata was saved locally',
          error: readError,
          stackTrace: readStackTrace,
        );
      }
      if (!mounted) return;
      final bool savedLocally = persisted != null &&
          persisted.name == stagedName &&
          persisted.note == stagedNote &&
          persisted.estimatedBirdsCount == stagedBirdCount;
      _showSaveMessage(
        savedLocally
            ? 'editRecording.messages.syncFailed'
            : 'editRecording.messages.saveFailed',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSaveMessage(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t(key))));
  }

  @override
  Widget build(BuildContext context) {
    final Color yellow = const Color(0xFFFFD641);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('editRecording.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _save,
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
                decoration: InputDecoration(
                  labelText: t('editRecording.fields.name'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: t('editRecording.fields.note'),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              Text(t('postRecordingForm.recordingForm.fields.birdCount.name')),
              const SizedBox(height: 5),
              Text(
                _strnadiCountController.toInt() == 3
                    ? t('postRecordingForm.recordingForm.fields.birdCount.count.threeOrMore')
                    : _strnadiCountController.toInt().toString(),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 5),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: yellow,
                  inactiveTrackColor: Colors.yellow.shade200,
                  thumbColor: yellow,
                  overlayColor: Colors.yellow.withOpacity(0.3),
                ),
                child: Slider(
                  value: _strnadiCountController,
                  min: 1,
                  max: 3,
                  divisions: 2,
                  onChanged: (value) =>
                      setState(() => _strnadiCountController = value),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t('editRecording.buttons.saveChanges')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
