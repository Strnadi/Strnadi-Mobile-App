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
 * recList.dart
 */

import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/recListItem.dart';


final logger = Logger();
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({Key? key}) : super(key: key);

  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

/// name | date | estimatedBirdsCount | downloaded
enum SortBy { name, date, ebc, downloaded, none }

class _RecordingScreenState extends State<RecordingScreen> {
  List<Recording> list = List<Recording>.empty(growable: true);

  SortBy sortOptions = SortBy.none;

  @override
  void initState() {
    super.initState();
    getRecordings();
  }

  void _showMessage(String message, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void getRecordings() async {
    List<Recording> recordings = await DatabaseNew.getRecordings();
    setState(() {
      list = recordings;
    });
  }

  void openRecording(Recording recording) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecordingItem(recording: recording),
        ),
      );
  }

  String formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }

  void FilterDownloaded() {
    List<Recording> recordings = list.where((element) => element.downloaded).toList();
    setState(() {
      list = recordings;
    });
  }


  void _showSortFilterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sort & Filter', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('Sort by Name'),
              onTap: () => {
                list.sort((a, b) => (b.name ?? '').toLowerCase().compareTo((a.name ?? '').toLowerCase())),
                setState(() {
                  sortOptions = SortBy.name;
                })
              }
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Sort by Date'),
              onTap: () =>
              {
                list.sort((a, b) => a.createdAt!.compareTo(b.createdAt!)),
                setState(() {
                  sortOptions = SortBy.date;
                })
              }
            ),
            ListTile(
              leading: const Icon(Icons.filter_list),
              title: const Text('Pocet ptaku'),
              onTap: () => {
                list.sort((a, b) => a.estimatedBirdsCount!.compareTo(b.estimatedBirdsCount!)),
                setState(() {
                  sortOptions = SortBy.ebc;
                })
              }
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Downloaded'),
              onTap: () => {
                FilterDownloaded(),
                setState(() {
                  sortOptions = SortBy.downloaded;
                })
              }
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Clear Filter'),
              onTap: () => {
                getRecordings(),
                setState(() {
                  sortOptions = SortBy.none;
                })
              }
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Recording> records = list.reversed.toList();
    records.forEach((rec) =>
        print('rec id ${rec.id} is ${rec.downloaded ? 'downloaded' : 'Not downloaded'} and is ${rec.sent ? 'sent' : 'not sent'}'));
    return ScaffoldWithBottomBar(
      logout: () => _showSortFilterOptions(context),
      icon: Icons.sort,
      appBarTitle: 'Záznamy',
      content: Padding(
        padding: const EdgeInsets.all(10.0),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: RefreshIndicator(
            onRefresh: () async {
              await DatabaseNew.syncRecordings();
              getRecordings();
            },
            child: records.isEmpty
                ? Center(child: Text('Zatím nemáte žádné nahrávky'))
                : ListView.separated(
              itemCount: records.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(
                    records[index].name ?? records[index].id?.toString() ?? 'Neznámý název',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  subtitle: SizedBox(
                    child: Row(
                      children: [
                        Text(
                          records[index].createdAt != null
                              ? formatDateTime(records[index].createdAt!)
                              : '',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          records[index].sent ? 'Odesláno' : 'Čeká na odeslání',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  trailing: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!records[index].sending && !records[index].sent)
                          IconButton(
                            icon: const Icon(Icons.file_upload, size: 20),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              DatabaseNew.sendRecording(
                                  records[index],
                                  DatabaseNew.getPartsById(records[index].id!)
                              ).onError((e, stackTrace) {
                                logger.e("An error has occurred: $e", stackTrace: stackTrace);
                                Sentry.captureException(e, stackTrace: stackTrace);
                              });
                            },
                          ),
                        if (!records[index].downloaded)
                          IconButton(
                            icon: const Icon(Icons.file_download, size: 20),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              DatabaseNew.downloadRecording(records[index].id!)
                                  .onError((e, stackTrace) {
                                if (e is UnimplementedError) {
                                  _showMessage("Tato funkce není dostupná na tomto zařízení", "Chyba");
                                }
                                logger.e("An error has occurred: $e", stackTrace: stackTrace);
                                Sentry.captureException(e, stackTrace: stackTrace);
                              });
                            },
                          ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  onTap: () => openRecording(records[index]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}