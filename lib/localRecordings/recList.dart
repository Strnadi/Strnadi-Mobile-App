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
import 'dart:io';

import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/localization/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:strnadi/api/http_adapter.dart' as http;
import 'package:logger/logger.dart';
import 'package:strnadi/database/Models/recording.dart';
import '../dialects/ModelHandler.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/incomplete_upload_prompt.dart';
import 'package:strnadi/localRecordings/recListItem.dart';
import 'package:strnadi/localRecordings/recording_dialect_summary.dart';
import 'package:strnadi/localRecordings/upload_integration_helpers.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/PostRecordingForm/recording_draft_handoff.dart';
import 'package:latlong2/latlong.dart';

import '../config/config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../navigation/notification_bell_button.dart';
import '../navigation/scaffold_with_bottom_bar.dart';
import '../navigation/session_navigation.dart';
import '../utils/location_label.dart';
import '../utils/async_single_flight.dart';

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

  bool compactView = false; // Default to detailed view

  Timer? _refreshTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  PageRoute<dynamic>? _subscribedRoute;
  final AsyncSingleFlight _sendAllSingleFlight = AsyncSingleFlight();
  bool _isSendingAll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure that the route is a PageRoute before subscribing.
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute && route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        routeObserver.unsubscribe(this);
      }
      routeObserver.subscribe(this, route);
      _subscribedRoute = route;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    routeObserver.unsubscribe(this);
    _subscribedRoute = null;
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when the current route has been popped back to.
    unawaited(getRecordings());
  }

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity()
        .checkConnectivity()
        .asStream()
        .listen(_handleInitialConnectivity);
    unawaited(getRecordings());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await IncompleteUploadPrompt.checkAndPrompt(context);
    });
    // Periodically refresh to catch sending status updates
    // _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    //   getRecordings();
    // });
  }

  void _handleInitialConnectivity(List<ConnectivityResult> results) {
    if (!mounted ||
        !results.every((result) => result == ConnectivityResult.none)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
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

  Future<void> getRecordings() async {
    final List<Recording> recordings = await DatabaseNew.getRecordings();
    if (!mounted) return;
    setState(() {
      list = recordings;
    });
  }

  Future<void> openRecording(Recording recording) async {
    if (!recording.captureReviewed) {
      await _resumeInterruptedRecordingDraft(recording);
      if (!mounted) return;
      await getRecordings();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecordingItem(recording: recording),
      ),
    );
    if (!mounted) return;
    await getRecordings(); // Refresh the list after returning
  }

  Future<void> _resumeInterruptedRecordingDraft(Recording recording) async {
    try {
      final int? recordingId = recording.id;
      final String recordingPath = recording.path?.trim() ?? '';
      if (recordingId == null ||
          recordingId <= 0 ||
          recordingPath.isEmpty ||
          !await File(recordingPath).exists()) {
        throw StateError('Interrupted recording audio is not readable.');
      }

      final List<RecordingPart> parts =
          await DatabaseNew.getPartsByRecordingId(recordingId);
      parts.sort(
        (RecordingPart first, RecordingPart second) =>
            first.startTime.compareTo(second.startTime),
      );
      for (final RecordingPart part in parts) {
        final String partPath = part.path?.trim() ?? '';
        if (partPath.isEmpty || !await File(partPath).exists()) {
          throw StateError('Interrupted recording part audio is not readable.');
        }
      }

      final RecordingDraftHandoff handoff =
          RecordingDraftHandoff.restorePersisted(
        recording: recording,
        recordingParts: parts,
      );
      final List<RecordingPartUnready> unreadyParts = parts
          .map(
            (RecordingPart part) => RecordingPartUnready(
              id: part.id,
              recordingId: part.recordingId,
              startTime: part.startTime,
              endTime: part.endTime,
              gpsLatitudeStart: part.gpsLatitudeStart,
              gpsLatitudeEnd: part.gpsLatitudeEnd,
              gpsLongitudeStart: part.gpsLongitudeStart,
              gpsLongitudeEnd: part.gpsLongitudeEnd,
              path: part.path,
            ),
          )
          .toList(growable: false);
      final List<int> durations = parts
          .map(
            (RecordingPart part) =>
                part.length ??
                part.endTime.difference(part.startTime).inSeconds,
          )
          .toList(growable: false);
      final List<LatLng> route = <LatLng>[];
      void addRoutePoint(double latitude, double longitude) {
        final LatLng point = LatLng(latitude, longitude);
        if (route.isEmpty ||
            route.last.latitude != point.latitude ||
            route.last.longitude != point.longitude) {
          route.add(point);
        }
      }

      for (final RecordingPart part in parts) {
        addRoutePoint(part.gpsLatitudeStart, part.gpsLongitudeStart);
        addRoutePoint(part.gpsLatitudeEnd, part.gpsLongitudeEnd);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (BuildContext context) => RecordingForm(
            filepath: recordingPath,
            startTime: recording.createdAt,
            currentPosition: route.isEmpty ? null : route.first,
            recordingParts: unreadyParts,
            recordingPartsTimeList: durations,
            route: route,
            persistedDraft: handoff,
          ),
        ),
      );
    } catch (error, stackTrace) {
      logger.e(
        'Failed to reopen an interrupted recording draft',
        error: error,
        stackTrace: stackTrace,
      );
      Sentry.captureException(error, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('recList.errors.reviewRecoveryFailed'))),
      );
    }
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
                  unawaited(getRecordings());
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

  Widget buildCompactRecordingItem(
      Recording rec, String dateText, VoidCallback openRec) {
    return InkWell(
      onTap: openRec,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            rec.name != null
                ? Text(
                    _truncateName(rec.name!, maxLength: 14),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  )
                : FutureBuilder<String?>(
                    future: () async {
                      var parts =
                          await DatabaseNew.getPartsByRecordingId(rec.id!);
                      if (parts.isEmpty) return rec.id?.toString();
                      String? text = await reverseGeocode(
                              parts[0].gpsLatitudeStart,
                              parts[0].gpsLongitudeStart) ??
                          rec.id?.toString();
                      rec.name = text;
                      return text;
                    }(),
                    builder: (context, snapshot) {
                      String topText;
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        topText = t('recList.name.loading');
                      } else if (snapshot.hasError || snapshot.data == null) {
                        topText =
                            rec.id?.toString() ?? t('recList.name.unknown');
                      } else {
                        topText = snapshot.data!;
                      }
                      return Text(
                        _truncateName(topText, maxLength: 10),
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
            VerticalDivider(width: 8),
            Text(
              dateText.split(' ').first,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            VerticalDivider(width: 8),
            FutureBuilder<String>(
              future: getDialectName(rec.id!),
              builder: (context, snapshot) {
                final txt = (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData)
                    ? snapshot.data!
                    : t('recList.dialect.loading');
                return Text(
                  txt,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                );
              },
            ),
            VerticalDivider(width: 8),
            Text(
              '${rec.estimatedBirdsCount}',
              style: TextStyle(fontSize: 12, color: Colors.amber[700]),
            ),
            VerticalDivider(width: 8),
            FutureBuilder<List<RecordingPart>>(
              future: Future.value(DatabaseNew.getPartsByRecordingId(rec.id!)),
              builder: (context, snapshot) {
                String status;
                Color color;
                if (!rec.captureReviewed) {
                  status = '📝';
                  color = Colors.orange;
                } else if (rec.sending) {
                  status = '🔵';
                  color = Colors.blue;
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  status = t('recList.status.checkingParts');
                  color = Colors.grey;
                } else if (snapshot.hasError) {
                  status = rec.sent ? '✅' : '❌';
                  color = rec.sent ? Colors.green : Colors.orange;
                } else {
                  final parts = snapshot.data!;
                  if (parts.any((p) => p.sending)) {
                    status = '🔵';
                    color = Colors.blue;
                  } else if (rec.sent && parts.any((p) => !p.sent)) {
                    status = '❌';
                    color = Colors.red;
                  } else {
                    status = rec.sent ? '✅' : '❌';
                    color = rec.sent ? Colors.green : Colors.orange;
                  }
                }
                return Text(
                  status,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600),
                );
              },
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Colors.grey, size: 18),
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
          int result = a.createdAt.compareTo(b.createdAt);
          return isAscending ? result : -result;
        });
        break;
      case SortBy.ebc:
        sortedList.sort((a, b) {
          int result = a.estimatedBirdsCount.compareTo(b.estimatedBirdsCount);
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
    return '${name.substring(0, maxLength)}...';
  }

  Future<void> sendAllUnsent() => _sendAllSingleFlight.run(_sendAllUnsentOnce);

  Future<void> _sendAllUnsentOnce() async {
    if (!mounted) return;
    setState(() => _isSendingAll = true);
    try {
      for (var rec in list) {
        if (!rec.captureReviewed) {
          continue;
        }
        if (recordingUploadIsActive(
          recordingSending: rec.sending,
          recordingLease: rec.uploadLease,
          partSendingStates: const <bool>[],
        )) {
          continue;
        }

        if (!rec.sent) {
          logger.i(
              "recording: ${rec.id} sent: ${rec.sent} sending: ${rec.sending}");
          try {
            final incompleteUploads = await DatabaseNew.findIncompleteUploads(
              recordingId: rec.id,
            );
            if (!mounted) return;
            if (incompleteUploads.isNotEmpty) {
              await IncompleteUploadPrompt.checkAndPrompt(
                context,
                recordingId: rec.id,
                oncePerSession: false,
              );
              if (!mounted) return;
              continue;
            }

            setState(() {
              rec.sending = true;
            });
            await DatabaseNew.sendRecordingBackground(rec.id!);
            if (!mounted) return;
            logger.i("Sending recording: ${rec.id}");
          } catch (e, stackTrace) {
            logger.e('Error during send check/resend: $e',
                error: e, stackTrace: stackTrace);
            Sentry.captureException(e, stackTrace: stackTrace);
            rec.sending = false;
            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('recList.errors.sendFailed'))),
              );
            }
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingAll = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Recording> records = list.reversed.toList();
    final bool hasUnsentRecordings =
        records.any((rec) => rec.captureReviewed && !rec.sent);
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
              '${t('recList.sort.myRecBy')} $sortName ${isAscending ? '↑' : '↓'}';
        } else {
          appBarTitle = t('recList.sort.myRecByDownloaded');
        }
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await navigateToSessionLanding(context);
      },
      child: Scaffold(
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
                icon:
                    Icon(compactView ? Icons.view_agenda : Icons.view_headline),
                tooltip: compactView
                    ? "Switch to detailed view"
                    : "Switch to compact view",
                onPressed: () => setState(() {
                  compactView = !compactView;
                }),
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                color: Colors.black,
                onPressed: () => _showSortFilterOptions(context),
                tooltip: t('recList.buttons.sortAndFilter'),
              ),
              const NotificationBellButton(),
            ]),
        body: Padding(
          padding: const EdgeInsets.all(10.0),
          child: RefreshIndicator(
            onRefresh: () async {
              await DatabaseNew.syncRecordings();
              if (!mounted) return;
              await DatabaseNew.checkSendingRecordings();
              if (!mounted) return;
              await getRecordings();
            },
            child: Column(
              children: [
                if (hasUnsentRecordings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSendingAll
                            ? null
                            : () => unawaited(sendAllUnsent()),
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
                            final dateText = formatDateTime(rec.createdAt);

                            if (compactView) {
                              return buildCompactRecordingItem(
                                  rec, dateText, () => openRecording(rec));
                            } else {
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
                                            color:
                                                Colors.black.withOpacity(0.05),
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
                                                        _truncateName(
                                                            rec.name!),
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      )
                                                    : FutureBuilder<String?>(
                                                        future: () async {
                                                          var parts =
                                                              await DatabaseNew
                                                                  .getPartsByRecordingId(
                                                                      rec.id!);
                                                          if (parts.isEmpty) {
                                                            return rec.id
                                                                ?.toString();
                                                          }
                                                          String? text = await reverseGeocode(
                                                                  parts[0]
                                                                      .gpsLatitudeStart,
                                                                  parts[0]
                                                                      .gpsLongitudeStart) ??
                                                              rec.id
                                                                  ?.toString();
                                                          rec.name = text;
                                                          return text;
                                                        }(),
                                                        builder: (context,
                                                            snapshot) {
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
                                                            _truncateName(
                                                                topText),
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                const SizedBox(height: 4),
                                                FutureBuilder<String>(
                                                  future:
                                                      getDialectName(rec.id!),
                                                  builder: (context, snapshot) {
                                                    String dialectText;
                                                    if (snapshot
                                                            .connectionState ==
                                                        ConnectionState
                                                            .waiting) {
                                                      dialectText = t(
                                                          'recList.dialect.loading');
                                                    } else if (snapshot
                                                            .hasError ||
                                                        snapshot.data == null) {
                                                      dialectText = t(
                                                          'recList.dialect.unknown');
                                                    } else {
                                                      dialectText =
                                                          snapshot.data!;
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
                                                FutureBuilder<
                                                    List<RecordingPart>>(
                                                  future: Future.value(
                                                      DatabaseNew
                                                          .getPartsByRecordingId(
                                                              rec.id!)),
                                                  builder: (context, snapshot) {
                                                    String status;
                                                    Color color;
                                                    if (!rec.captureReviewed) {
                                                      status = t(
                                                          'recList.status.finishReview');
                                                      color = Colors.orange;
                                                    } else if (rec.sending) {
                                                      status = t(
                                                          'recList.status.sending');
                                                      color = Colors.blue;
                                                    } else if (snapshot
                                                            .connectionState ==
                                                        ConnectionState
                                                            .waiting) {
                                                      status = t(
                                                          'recList.status.checkingParts');
                                                      color = Colors.grey;
                                                    } else if (snapshot
                                                        .hasError) {
                                                      status = rec.sent
                                                          ? t('recList.status.uploaded')
                                                          : t('recList.status.waitingForUpload');
                                                      color = rec.sent
                                                          ? Colors.green
                                                          : Colors.orange;
                                                    } else {
                                                      final parts =
                                                          snapshot.data!;
                                                      if (parts.any(
                                                          (p) => p.sending)) {
                                                        status = t(
                                                            'recList.status.sendingParts');
                                                        color = Colors.blue;
                                                      } else if (rec.sent &&
                                                          parts.any(
                                                              (p) => !p.sent)) {
                                                        logger.w(
                                                          'Recording ${rec.id} '
                                                          'has ${parts.where((p) => !p.sent).length} '
                                                          'unsent parts.',
                                                        );
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
                                                        fontWeight:
                                                            FontWeight.w600,
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
                            }
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
      ),
    );
  }

  Future<String?> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

    logger.i('Reverse geocoding a recording location.');
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.mapsApiKey}',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final String? label = buildLocationLabel(data);
        if (label != null) return label;
      } else {
        logger.e(
            "Reverse geocode failed with status code ${response.statusCode}");
        return null;
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
    return null;
  }

  Future<String> getDialectName(int recordingId) async {
    try {
      final detectedDialects =
          await DatabaseNew.getDetectedDialectsByRecordingLocalId(recordingId);
      final List<Dialect> legacyDialects =
          await DatabaseNew.getDialectsByRecordingId(recordingId);

      final selection = selectRecordingDialectSummary(
        detectedRows: detectedDialects.map(
          (dialect) => RecordingDialectSummaryRow(
            adminConfirmed: dialect.confirmedDialect,
            aiPredicted: dialect.predictedDialect,
            manualGuess: dialect.userGuessDialect,
          ),
        ),
        legacyRows: legacyDialects.map(
          (dialect) => RecordingDialectSummaryRow(
            adminConfirmed: dialect.adminDialect,
            manualGuess: dialect.userGuessDialect,
          ),
        ),
      );

      return formatRecordingDialectSummary(
        selection,
        unknownLabel: t('recList.dialect.unknown'),
        withoutDialectLabel: t('recList.dialect.without'),
        localizeDialect: DialectKeywordTranslator.toLocalized,
      );
    } catch (e, stackTrace) {
      logger.e('Error fetching dialects for recording $recordingId: $e',
          error: e, stackTrace: stackTrace);
      return t('recList.dialect.unknown');
    }
  }

  AssetImage getDialectImage(String dialectName) {
    //TODO load actual image
    return AssetImage('assets/images/dialect.png');
  }
}
