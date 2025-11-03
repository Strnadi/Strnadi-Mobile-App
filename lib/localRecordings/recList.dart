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

import 'dart:convert';

import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/localization/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:strnadi/database/Models/recording.dart';
import '../database/fileSize.dart';
import '../dialects/ModelHandler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/recListItem.dart';

import '../config/config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../exceptions.dart';

final logger = Logger();

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({Key? key}) : super(key: key);

  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

/// name | date | estimatedBirdsCount | downloaded
enum SortBy { name, date, ebc, downloaded, none }

class _RecordingScreenState extends State<RecordingScreen> with RouteAware {
  List<Recording> list = List<Recording>.empty(growable: true);

  SortBy sortOptions = SortBy.date;

  bool isAscending = true; // Add

  Timer? _refreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure that the route is a PageRoute before subscribing.
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when the current route has been popped back to.
    getRecordings();
  }

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then((result) {
      if (result == ConnectivityResult.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(t('recList.offlineMode.title')),
              content: Text(t('recList.offlineMode.message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('auth.buttons.ok')),
                ),
              ],
            ),
          );
        });
      }
    });
    getRecordings();
    // Periodically refresh to catch sending status updates
    // _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    //   getRecordings();
    // });
  }

  void _showMessage(String message, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('auth.buttons.ok'))),
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

  void openRecording(Recording recording) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordingItem(recording: recording),
      ),
    );
    getRecordings(); // Refresh the list after returning
  }

  String formatDateTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} $h:$m';
  }

  void FilterDownloaded() {
    List<Recording> recordings =
        list.where((element) => element.downloaded).toList();
    recordings += list.where((element) => !element.sent).toList();
    recordings += list.where((element) => element.sending).toList();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('recList.buttons.sortAndFilter'),
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: Text(t('recList.buttons.sortByName')),
                // Highlight active sort option
                tileColor: sortOptions == SortBy.name
                    ? Colors.grey.withOpacity(0.2)
                    : null,
                onTap: () {
                  if (sortOptions == SortBy.name) {
                    isAscending = !isAscending; // Toggle sorting order
                  }
                  setState(() {
                    sortOptions = SortBy.name;
                    _applySorting();
                  });
                  Navigator.pop(context);
                }),
            ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(t('recList.buttons.sortByDate')),
                tileColor: sortOptions == SortBy.date
                    ? Colors.grey.withOpacity(0.2)
                    : null,
                onTap: () {
                  setState(() {
                    if (sortOptions == SortBy.date) {
                      isAscending = !isAscending; // Toggle sorting order
                    }
                    sortOptions = SortBy.date;
                    _applySorting();
                  });
                  Navigator.pop(context);
                }),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.download),
                title: Text(t('recList.buttons.filterDownloaded')),
                tileColor: sortOptions == SortBy.downloaded
                    ? Colors.grey.withOpacity(0.2)
                    : null,
                onTap: () {
                  FilterDownloaded();
                  setState(() {
                    if (sortOptions == SortBy.downloaded) {
                      isAscending = !isAscending; // Toggle sorting order
                    }
                    sortOptions = SortBy.downloaded;
                  });
                  Navigator.pop(context);
                }),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.clear),
                title: Text(t('recList.buttons.clearFilter')),
                onTap: () {
                  getRecordings();
                  setState(() {
                    sortOptions = SortBy.none;
                    isAscending = true; // Reset to default
                  });
                  Navigator.pop(context);
                }),
          ],
        ),
      ),
    );
  }

  void _applySorting() {
    List<Recording> sortedList = List.from(list);
    switch (sortOptions) {
      case SortBy.name:
        sortedList.sort((a, b) {
          int result = (a.name ?? '')
              .toLowerCase()
              .compareTo((b.name ?? '').toLowerCase());
          return isAscending ? result : -result;
        });
        break;
      case SortBy.date:
        sortedList.sort((a, b) {
          int result = a.createdAt!.compareTo(b.createdAt!);
          return isAscending ? result : -result;
        });
        break;
      case SortBy.ebc:
        sortedList.sort((a, b) {
          int result = a.estimatedBirdsCount!.compareTo(b.estimatedBirdsCount!);
          return isAscending ? result : -result;
        });
        break;
      default:
        break;
    }
    setState(() {
      list = sortedList;
    });
  }

  String _truncateName(String name, {int maxLength = 20}) {
    if (name.length <= maxLength) {
      return name;
    }
    return name.substring(0, maxLength) + '...';
  }

  void sendAllUnsent() async {
    for (var rec in list) {
      if (!rec.sent || rec.sending) {
        logger.i(
            "recording: ${rec.id} sent: ${rec.sent} sending: ${rec.sending}");
        try {
          setState(() {
            rec.sending = true;
          });
          DatabaseNew.sendRecordingBackground(rec.id!);
          logger.i("Sending recording: ${rec.id}");
          await DatabaseNew.checkRecordingPartsSent(rec.id!);
        } on UnsentPartsException {
          // prompt to resend unsent parts
          final shouldResend = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t('recList.status.unsentParts')),
              content: Text(t('recListItem.dialogs.unsentParts.message')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(t('recListItem.dialogs.confirmDelete.cancel'))),
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(t('recListItem.buttons.resendUnsentParts'))),
              ],
            ),
          );
          if (shouldResend == true) {
            await DatabaseNew.resendUnsentParts();
          }
        } catch (e, stackTrace) {
          logger.e('Error during send check/resend: $e',
              error: e, stackTrace: stackTrace);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Recording> records = list.reversed.toList();
    records.forEach((rec) => print(
        'rec id ${rec.id} is ${rec.downloaded ? 'downloaded' : 'Not downloaded'} and is ${rec.sent ? 'sent' : 'not sent'}'));

    // Create a title that shows current filter
    String appBarTitle = t('recList.title');
    if (sortOptions != SortBy.none) {
      String sortName = '';
      switch (sortOptions) {
        case SortBy.name:
          sortName = t('recList.sort.name');
          break;
        case SortBy.date:
          sortName = t('recList.sort.date');
          break;
        case SortBy.ebc:
          sortName = t('recList.sort.birdCount');
          break;
        case SortBy.downloaded:
          sortName = t('recList.sort.downloaded');
          break;
        default:
          sortName = '';
      }

      if (sortName.isNotEmpty) {
        if (sortOptions != SortBy.downloaded) {
          appBarTitle =
              '${t('recList.sort.myRecBy')} $sortName ${isAscending ? '↑' : '↓'})';
        } else {
          appBarTitle = t('recList.sort.myRecByDownloaded');
        }
      }
    }

    Color yellow = const Color(0xFFFFD641);

    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              appBarTitle,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                fontFamily: 'Bricolage Grotesque',
              ),
            ),
          ),
          centerTitle: false,
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.sort),
              color: Colors.black,
              onPressed: () => _showSortFilterOptions(context),
              tooltip: t('recList.buttons.sortAndFilter'),
            ),
          ]),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: RefreshIndicator(
          onRefresh: () async {
            await DatabaseNew.syncRecordings();
            getRecordings();
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => sendAllUnsent(),
                    icon: const Icon(Icons.send),
                    label: Text(t('recList.buttons.sendAllUnsent')),
                  ),
                ),
              ),
              Expanded(
                child: records.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: 500,
                            child: Center(
                                child: Text(t('recList.emptyListMessage'))),
                          )
                        ],
                      )
                    : ListView.separated(
                        itemCount: records.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final rec = records[index];
                          final dateText = rec.createdAt != null
                              ? formatDateTime(rec.createdAt!)
                              : '';

                          return InkWell(
                              onTap: () => openRecording(rec),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            rec.name != null
                                                ? Text(
                                                    _truncateName(rec.name!),
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  )
                                                : FutureBuilder<String?>(
                                                    future: () async {
                                                      var parts = await DatabaseNew
                                                          .getPartsByRecordingId(
                                                              rec.id!);
                                                      if (parts.isEmpty) {
                                                        return rec.id
                                                            ?.toString();
                                                      }
                                                      String? text =
                                                          await reverseGeocode(
                                                                  parts[0]
                                                                      .gpsLatitudeStart,
                                                                  parts[0]
                                                                      .gpsLongitudeStart) ??
                                                              rec.id
                                                                  ?.toString();
                                                      rec.name = text;
                                                      return text;
                                                    }(),
                                                    builder:
                                                        (context, snapshot) {
                                                      String topText;
                                                      if (snapshot
                                                              .connectionState ==
                                                          ConnectionState
                                                              .waiting) {
                                                        topText = t(
                                                            'recList.name.loading');
                                                      } else if (snapshot
                                                              .hasError ||
                                                          snapshot.data ==
                                                              null) {
                                                        topText = rec.id
                                                                ?.toString() ??
                                                            t('recList.name.unknown');
                                                      } else {
                                                        topText =
                                                            snapshot.data!;
                                                      }
                                                      return Text(
                                                        _truncateName(topText),
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                            const SizedBox(height: 4),
                                            FutureBuilder<String>(
                                              future: getDialectName(rec.id!),
                                              builder: (context, snapshot) {
                                                String dialectText;
                                                if (snapshot.connectionState ==
                                                    ConnectionState.waiting) {
                                                  dialectText = t(
                                                      'recList.dialect.loading');
                                                } else if (snapshot.hasError ||
                                                    snapshot.data == null) {
                                                  dialectText = t(
                                                      'recList.dialect.unknown');
                                                } else {
                                                  dialectText = snapshot.data!;
                                                }
                                                return Text(
                                                  dialectText,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        // Right Column
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            FutureBuilder<List<RecordingPart>>(
                                              future: Future.value(DatabaseNew
                                                  .getPartsByRecordingId(
                                                      rec.id!)),
                                              builder: (context, snapshot) {
                                                String status;
                                                Color color;
                                                if (rec.sending) {
                                                  status = t(
                                                      'recList.status.sending');
                                                  color = Colors.blue;
                                                } else if (snapshot
                                                        .connectionState ==
                                                    ConnectionState.waiting) {
                                                  status = t(
                                                      'recList.status.checkingParts');
                                                  color = Colors.grey;
                                                } else if (snapshot.hasError) {
                                                  status = rec.sent
                                                      ? t('recList.status.uploaded')
                                                      : t('recList.status.waitingForUpload');
                                                  color = rec.sent
                                                      ? Colors.green
                                                      : Colors.orange;
                                                } else {
                                                  final parts = snapshot.data!;
                                                  if (rec.sent &&
                                                      parts.any(
                                                          (p) => !p.sent)) {
                                                    logger.w(
                                                        'Unsent parts found');
                                                    String partsS = "";
                                                    for (var part in parts) {
                                                      partsS +=
                                                          '${part.toJson()}\n';
                                                    }
                                                    logger.w(
                                                        'All parts: $partsS');
                                                    status = t(
                                                        'recList.status.unsentParts');
                                                    color = Colors.red;
                                                  } else {
                                                    status = rec.sent
                                                        ? t('recList.status.uploaded')
                                                        : t('recList.status.waitingForUpload');
                                                    color = rec.sent
                                                        ? Colors.green
                                                        : Colors.orange;
                                                  }
                                                }
                                                return Text(
                                                  status,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: color,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              dateText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const Icon(Icons.chevron_right,
                                                color: Colors.grey),
                                          ],
                                        ),
                                      ])));
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ReusableBottomAppBar(
        currentPage: BottomBarItem.list,
        changeConfirmation: () => Future.value(true),
      ),
    );
  }

  Future<String?> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

    logger.i("reverse geocode url: $url");
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.mapsApiKey}',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final results = data['items'];
        if (results.isNotEmpty) {
          logger.i("Reverse geocode result: $results");
          return results[0]['name'];
        }
      } else {
        logger.e(
            "Reverse geocode failed with status code ${response.statusCode}");
        return null;
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  Future<String> getDialectName(int recordingId) async {
    try {
      // Prefer locally‑stored dialects to avoid an extra API call.
      final List<Dialect> dialects =
          await DatabaseNew.getDialectsByRecordingId(recordingId);

      if (dialects.isEmpty) {
        return t('recList.dialect.without');
      }

      // Return the first non‑empty, non‑placeholder dialect we find.
      for (final d in dialects) {
        final String? name = d.userGuessDialect;
        if (name != null &&
            name.isNotEmpty &&
            name != t('recList.dialect.undetermined')) {
          return name;
        }
      }

      // If every dialect string is empty or "Nevyhodnoceno", fall back.
      return t('recList.dialect.unknown');
    } catch (e, stackTrace) {
      logger.e('Error fetching dialects for recording $recordingId: $e',
          error: e, stackTrace: stackTrace);
      return t('recList.dialect.unknown');
    }
  }

  AssetImage getDialectImage(dialectName) {
    //TODO load actual image
    return AssetImage('assets/images/dialect.png');
  }
}
