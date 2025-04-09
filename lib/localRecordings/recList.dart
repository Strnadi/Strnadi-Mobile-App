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

import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/recListItem.dart';

import '../config/config.dart';

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

  SortBy sortOptions = SortBy.none;

  bool isAscending = true; // Add

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
    getRecordings();
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Třídění a filtry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ListTile(
                leading: const Icon(Icons.sort_by_alpha),
                title: const Text('Třídit podle názvu'),
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
                title: const Text('Třídit podle data'),
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
                title: const Text('Počet ptáků'),
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
                title: const Text('Stažené'),
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
                title: const Text('Zrušit filtr'),
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
    switch (sortOptions) {
      case SortBy.name:
        list.sort((a, b) {
          int result = (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
          return isAscending ? result : -result;
        });
        break;
      case SortBy.date:
        list.sort((a, b) {
          int result = a.createdAt!.compareTo(b.createdAt!);
          return isAscending ? result : -result;
        });
        break;
      case SortBy.ebc:
        list.sort((a, b) {
          int result = a.estimatedBirdsCount!.compareTo(b.estimatedBirdsCount!);
          return isAscending ? result : -result;
        });
        break;
      default:
        break;
    }
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
    String appBarTitle = 'Záznamy';
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
          appBarTitle = 'Záznamy (by $sortName ${isAscending ? '↑' : '↓'})';
        } else {
          appBarTitle = 'Záznamy (Pouze stažené)';
        }
      }
    }

    return ScaffoldWithBottomBar(
      logout: () => _showSortFilterOptions(context),
      icon: Icons.sort,
      appBarTitle:appBarTitle,
      content: Padding(
        padding: const EdgeInsets.all(10.0),
        child: RefreshIndicator(
          onRefresh: () async {
            await DatabaseNew.syncRecordings();
            getRecordings();
          },
          child: records.isEmpty
              ? const Center(child: Text('Zatím nemáte žádné záznamy'))
              : ListView.separated(
            itemCount: records.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final rec = records[index];
              final statusText = rec.sent ? 'Nahráno' : 'Čeká na nahrání';
              final statusColor = rec.sent ? Colors.green : Colors.orange;
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
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : FutureBuilder<String?> (
                                  future: () async {
                                    var parts = DatabaseNew.getPartsById(rec.id!);
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
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 4),
                          Text(
                            getDialectName(rec.id!),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      // Right Column
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateText,
                            style: const TextStyle(
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
      )
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
        final data = jsonDecode(response.body);
        final results = data['items'];
        if (results.isNotEmpty) {
          logger.i("Reverse geocode result: $results");
          setState(() {
            return results[0]['name'];
          });
        }
      }
      else {
        logger.e("Reverse geocode failed with status code ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: ${e.toString()}', error: e, stackTrace: stackTrace);
    }
  }

  String getDialectName(int id) {
    //TODO Load dialect name from database
    return 'Default Dialect'; // Placeholder for actual dialect name retrieval
  }

  AssetImage getDialectImage(dialectName) {
    //TODO load actual image
    return AssetImage('assets/images/dialect.png');
  }
}