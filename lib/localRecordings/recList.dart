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

import 'package:strnadi/localization/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../dialects/ModelHandler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/recListItem.dart';

import '../config/config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
    _refreshTimer?.cancel();
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
              title: Text(t('Offline režim')),
              content: Text(t('Jste offline. Budou dostupné pouze lokálně uložené záznamy.')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('OK')),
                ),
              ],
            ),
          );
        });
      }
    });
    getRecordings();
    // Periodically refresh to catch sending status updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      getRecordings();
    });
  }

  void _showMessage(String message, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('OK'))),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t('Třídění a filtry'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: Text(t('Třídit podle názvu')),
                // Highlight active sort option
                tileColor: sortOptions == SortBy.name ? Colors.grey.withOpacity(0.2) : null,
                onTap: () {
                  if (sortOptions == SortBy.name) {
                    isAscending = !isAscending; // Toggle sorting order
                  }
                  setState(() {
                    sortOptions = SortBy.name;
                    _applySorting();
                  });
                  Navigator.pop(context);
                }
            ),
            ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(t('Třídit podle data')),
                tileColor: sortOptions == SortBy.date ? Colors.grey.withOpacity(0.2) : null,
                onTap: () {
                  setState(() {
                    if (sortOptions == SortBy.date) {
                      isAscending = !isAscending; // Toggle sorting order
                    }
                    sortOptions = SortBy.date;
                    _applySorting();
                  });
                  Navigator.pop(context);
                }
            ),
            ListTile(
                leading: const Icon(Icons.filter_list),
                title: Text(t('Počet ptáků')),
                tileColor: sortOptions == SortBy.ebc ? Colors.grey.withOpacity(0.2) : null,
                onTap: () {
                  if (sortOptions == SortBy.ebc) {
                    isAscending = !isAscending; // Toggle sorting order
                  }
                  setState(() {
                    sortOptions = SortBy.ebc;
                    _applySorting();
                  });
                  Navigator.pop(context);
                }
            ),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.download),
                title: Text(t('Stažené')),
                tileColor: sortOptions == SortBy.downloaded ? Colors.grey.withOpacity(0.2) : null,
                onTap: () {
                  FilterDownloaded();
                  setState(() {
                    if (sortOptions == SortBy.downloaded) {
                      isAscending = !isAscending; // Toggle sorting order
                    }
                    sortOptions = SortBy.downloaded;
                  });
                  Navigator.pop(context);
                }
            ),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.clear),
                title: Text(t('Zrušit filtr')),
                onTap: () {
                  getRecordings();
                  setState(() {
                    sortOptions = SortBy.none;
                    isAscending = true; // Reset to default
                  });
                  Navigator.pop(context);
                }
            ),
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
          int result = (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
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



  @override
  Widget build(BuildContext context) {
    List<Recording> records = list.reversed.toList();
    records.forEach((rec) =>
        print('rec id ${rec.id} is ${rec.downloaded ? 'downloaded' : 'Not downloaded'} and is ${rec.sent ? 'sent' : 'not sent'}'));

    // Create a title that shows current filter
    String appBarTitle = 'Moje nahrávky';
    if (sortOptions != SortBy.none) {
      String sortName = '';
      switch (sortOptions) {
        case SortBy.name: sortName = 'Název'; break;
        case SortBy.date: sortName = 'Datum'; break;
        case SortBy.ebc: sortName = 'Počet ptáků'; break;
        case SortBy.downloaded: sortName = 'Pouze stažené'; break;
        default: sortName = '';
      }

      if (sortName.isNotEmpty) {
        if (sortOptions != SortBy.downloaded) {
          appBarTitle = 'Moje nahrávky (podle $sortName ${isAscending ? '↑' : '↓'})';
        } else {
          appBarTitle = 'Moje nahrávky (Pouze stažené)';
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
            icon: Image.asset('assets/icons/sort.png', width: 30, height: 30),
            onPressed: () => _showSortFilterOptions(context),
          )
        ]
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: RefreshIndicator(
          onRefresh: () async {
            await DatabaseNew.syncRecordings();
            getRecordings();
          },
          child: records.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 500,
                      child: Center(child: Text(t('Zatím nemáte žádné záznamy'))),
                    )
                  ],
                )
              : ListView.separated(
            itemCount: records.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rec = records[index];
              final dateText = rec.createdAt != null
                  ? formatDateTime(rec.createdAt!)
                  : '';

              return InkWell(
                onTap: () => openRecording(rec),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          rec.name != null
                              ? Text(
                                  _truncateName(rec.name!),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : FutureBuilder<String?> (
                                  future: () async {
                                    var parts = await DatabaseNew.getPartsById(rec.id!);
                                    if (parts.isEmpty) {
                                      return rec.id?.toString();
                                    }
                                    String? text = await reverseGeocode(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart) ?? rec.id?.toString();
                                    rec.name = text;
                                    return text;
                                  }(),
                                  builder: (context, snapshot) {
                                    String topText;
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      topText = 'Načítání...';
                                    } else if (snapshot.hasError || snapshot.data == null) {
                                      topText = rec.id?.toString() ?? 'Neznámý název';
                                    } else {
                                      topText = snapshot.data!;
                                    }
                                    return Text(
                                      _truncateName(topText),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 4),
                          FutureBuilder<String>(
                            future: getDialectName(rec.id!),
                            builder: (context, snapshot) {
                              String dialectText;
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                dialectText = 'Načítání dialektu...';
                              } else if (snapshot.hasError || snapshot.data == null) {
                                dialectText = 'Neznámý dialekt';
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
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FutureBuilder<List<RecordingPart>>(
                            future: Future.value(DatabaseNew.getPartsById(rec.id!)),
                            builder: (context, snapshot) {
                              String status;
                              Color color;
                              if (rec.sending) {
                                status = 'Odesílání...';
                                color = Colors.blue;
                              } else if (snapshot.connectionState == ConnectionState.waiting) {
                                status = 'Kontrola částí...';
                                color = Colors.grey;
                              } else if (snapshot.hasError) {
                                status = rec.sent ? 'Nahráno' : 'Čeká na nahrání';
                                color = rec.sent ? Colors.green : Colors.orange;
                              } else {
                                final parts = snapshot.data!;
                                if (rec.sent && parts.any((p) => !p.sent)) {
                                  logger.w('Unsent parts found');
                                  String partsS="";
                                  for (var part in parts) {partsS += '${part.toJson()}\n';}
                                  logger.w('All parts: $partsS');
                                  status = 'Neodeslané části';
                                  color = Colors.red;
                                } else {
                                  status = rec.sent ? 'Nahráno' : 'Čeká na nahrání';
                                  color = rec.sent ? Colors.green : Colors.orange;
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
                          const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ]
                  )
                )
              );
            },
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
    final url = Uri.parse("https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

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
      }
      else {
        logger.e("Reverse geocode failed with status code ${response.statusCode}");
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
        return 'Bez dialektu';
      }

      // Return the first non‑empty, non‑placeholder dialect we find.
      for (final d in dialects) {
        final String? name = d.userGuessDialect;
        if (name != null && name.isNotEmpty && name != 'Nevyhodnoceno') {
          return name;
        }
      }

      // If every dialect string is empty or "Nevyhodnoceno", fall back.
      return 'Neznámý dialekt';
    } catch (e, stackTrace) {
      logger.e('Error fetching dialects for recording $recordingId: $e',
          error: e, stackTrace: stackTrace);
      return 'Neznámý dialekt';
    }
  }

  AssetImage getDialectImage(dialectName) {
    //TODO load actual image
    return AssetImage('assets/images/dialect.png');
  }
}