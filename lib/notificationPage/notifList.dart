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
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localization/localization.dart';

class NotificationScreen extends StatefulWidget {
  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

// Local holder for part progress
class _PartProgress {
  final int partId;
  final double progress; // 0..1 or NaN/invalid
  _PartProgress(this.partId, this.progress);
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> notifications = [];

  @override
  void initState() {
    super.initState();
    getNotifications();
  }

  void getNotifications() async {
    final list = await DatabaseNew.getNotificationList();
    if (!mounted) return;
    setState(() {
      notifications = list;
    });
  }

  /// Resolve a human-friendly title for a recording.
  /// Tries to get the recording name; falls back to "Recording #<id>".
  Future<String> _resolveRecordingTitle(int recId) async {
    String fallback = 'Recording #$recId';
    try {
      // Try several likely DatabaseNew accessors defensively
      final Recording? rec = await DatabaseNew.getRecordingFromDbById(recId);
      final String? result = rec?.name?.trim();
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // Swallow and use fallback
    }
    try {
      // TODO: Implement reverse geocode
    } catch (_) {
      // Swallow and use fallback
    }
    return fallback;
  }


  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.notification,
      appBarTitle: t('notifications.title'),
      content: Column(
        children: [
          // Active uploads panel
          StreamBuilder<Map<int, double>>(
            stream: UploadProgressBus.stream,
            initialData: UploadProgressBus.snapshot,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const {};
              // Map recordingId -> list of part progresses
              final Map<int, List<_PartProgress>> grouped = <int, List<_PartProgress>>{};

              // Build grouping by recording id
              data.forEach((partId, rawProgress) {
                double progress = rawProgress;
                if (progress.isNaN) progress = 0.0;

                int recId = -1;
                try {
                  final part = DatabaseNew.getRecordingPartById(partId);
                  // Use the local RecordingPart.recordingId as the only source of truth
                  recId = part?.recordingId is int
                      ? part!.recordingId
                      : int.tryParse('${part?.recordingId}') ?? -1;
                } catch (_) {
                  recId = -1; // unknown / orphan part
                }

                grouped
                    .putIfAbsent(recId, () => <_PartProgress>[])
                    .add(_PartProgress(partId, progress));
              });

              // Flatten to a deterministic order: unknown id (-1) last
              final recIds = grouped.keys.toList()
                ..sort((a, b) {
                  if (a == -1 && b != -1) return 1;
                  if (b == -1 && a != -1) return -1;
                  return a.compareTo(b);
                });

              debugPrint('[notifList] UploadProgressBus builder: hasData=' + (snapshot.hasData).toString() + ', recordings=' + recIds.length.toString());

              return Card(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.upload_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t('notifications.uploads_in_progress'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (data.isEmpty)
                        Text(
                          t('notifications.no_uploads'),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      else
                        // For each recording render a card with its parts as progress bars
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recIds.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final recId = recIds[idx];
                            final parts = grouped[recId]!;

                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.mic_rounded, size: 18),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: FutureBuilder<String>(
                                          future: recId == -1
                                              ? Future.value(t('notifications.unknown_recording'))
                                              : _resolveRecordingTitle(recId),
                                          builder: (context, snap) {
                                            final title = snap.data ?? 'Recording #$recId';
                                            return Text(
                                              title,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            );
                                          },
                                        ),
                                      ),
                                      if (recId != -1)
                                        Text('#$recId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // List each part with its progress bar
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: parts.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                                    itemBuilder: (context, i) {
                                      final part = parts[i];
                                      final pct = (part.progress * 100).clamp(0, 100).toStringAsFixed(0);
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Part #${part.partId} – $pct%', style: const TextStyle(fontSize: 12)),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: (part.progress >= 0.0 && part.progress <= 1.0)
                                                ? part.progress
                                                : null,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Notifications list
          Expanded(
            child: notifications.isEmpty
                ? Center(
                    child: Text(
                      t('notifications.no_notifications'),
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return ListTile(
                        title: Text(
                          notification.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(notification.message),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(notification.time, style: const TextStyle(color: Colors.grey)),
                            if (notification.unread)
                              const Icon(Icons.circle, color: Colors.black, size: 10),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class NotificationItem {
  final String title;
  final String message;
  final String time;
  final bool unread;

  NotificationItem({
    required this.title,
    required this.message,
    required this.time,
    required this.unread,
  });
}