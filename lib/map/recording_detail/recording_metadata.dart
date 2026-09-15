import 'package:flutter/material.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/userData.dart';
import 'package:strnadi/localRecordings/userBadge.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/widgets/recording_note_card.dart';

class RecordingMetadata extends StatelessWidget {
  const RecordingMetadata({
    super.key,
    required this.recording,
    required this.user,
    required this.dialects,
  });

  final Recording recording;
  final UserData? user;
  final Widget dialects;

  @override
  Widget build(BuildContext context) {
    final date = recording.createdAt;
    final decoration = BoxDecoration(
      border: Border.all(color: Colors.grey),
      borderRadius: BorderRadius.circular(10),
    );
    return Column(
      children: [
        if (user != null) UserBadge(user: user!),
        const SizedBox(height: 20),
        RecordingNoteCard(
          note: recording.note?.trim().isNotEmpty == true
              ? recording.note!
              : t('recListItem.notePlaceholder'),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(13),
          width: double.infinity,
          decoration: decoration,
          child: Column(
            children: [
              Text(t('recListItem.dateTime')),
              Text(
                '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute}',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        dialects,
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: decoration,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${t('recListItem.estimatedBirdsCount')}: '),
              Text(recording.estimatedBirdsCount.toString()),
            ],
          ),
        ),
      ],
    );
  }
}
