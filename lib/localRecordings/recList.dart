/*
 * recList.dart
 */

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/recListItem.dart';
import 'package:strnadi/archived/recordingsDb.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({Key? key}) : super(key: key);

  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  List<Recording> list = List<Recording>.empty(growable: true);

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
    if (recording.downloaded) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RecordingItem(recording: recording),
        ),
      );
    }
  }

  String formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }

  @override
  Widget build(BuildContext context) {
    List<Recording> records = list.reversed.toList();
    records.forEach((rec) =>
        print('rec id ${rec.id} is ${rec.downloaded ? 'downloaded' : 'Not downloaded'} and is ${rec.sent ? 'sent' : 'not sent'}'));
    return ScaffoldWithBottomBar(
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