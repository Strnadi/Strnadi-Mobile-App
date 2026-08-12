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
 * RecordingForm.dart
 */

import 'dart:io';
import 'package:flutter/cupertino.dart' as Dialogs;
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/localization/localization.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/api/http_adapter.dart' as http;
import 'package:strnadi/auth/activated_auth_session.dart';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/recording/streamRec.dart';
import '../auth/authorizator.dart';
import '../config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'addDialect.dart';
import 'recording_draft_handoff.dart';
import 'recording_form_rendering.dart';
import 'dart:math' as math;
import 'package:strnadi/dialects/ModelHandler.dart';

final MAPY_CZ_API_KEY = Config.mapsApiKey;
final logger = Logger();

class RecordingForm extends StatefulWidget {
  final String filepath;
  final LatLng? currentPosition;
  final List<RecordingPartUnready> recordingParts;
  final DateTime startTime;
  final List<int> recordingPartsTimeList;
  final List<LatLng> route;
  final RecordingDraftHandoff? persistedDraft;

  const RecordingForm({
    Key? key,
    required this.filepath,
    required this.startTime,
    required this.currentPosition,
    required this.recordingParts,
    required this.recordingPartsTimeList,
    required this.route,
    this.persistedDraft,
  }) : super(key: key);

  @override
  _RecordingFormState createState() => _RecordingFormState();
}

class _RecordingFormState extends State<RecordingForm> {
  final _recordingNameController = TextEditingController();
  final _commentController = TextEditingController();
  double _strnadiCountController = 1.0;
  double currentPos = 0.0;
  List<DialectModel> dialectSegments = [];
  final _audioPlayer = AudioPlayer();
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration?>? _audioDurationSubscription;
  StreamSubscription<bool>? _audioPlayingSubscription;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  Duration currentPositionDuration = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool isPlaying = false;
  late Recording recording;
  int? _recordingId;
  bool _draftPersistenceMayHaveCommitted = false;
  final List<LatLng> _route = [];
  // This will hold the converted parts.
  List<RecordingPart> recordingParts = [];
  Object? _recordingPartsConversionError;
  late final Future<void> _recordingOwnerReady;
  late final Future<String> _deviceModelFuture;

  final MapController _mapController = MapController();

  late String placeTitle = " ";

  bool _isLoading = false;
  bool _isDiscarding = false;

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  /// Runs [action] with the loader on, prevents duplicate presses.
  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // ignore re-press
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  @override
  void initState() {
    super.initState();

    setState(() {
      placeTitle = " ";
    });

    _audioPositionSubscription = _audioPlayer.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        currentPositionDuration = position;
      });
    });
    _audioDurationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() {
        totalDuration = duration ?? Duration.zero;
      });
    });
    _audioPlayingSubscription = _audioPlayer.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        isPlaying = playing;
      });
    });
    _audioStateSubscription =
        _audioPlayer.playerStateStream.listen((playerState) {
      if (!mounted) return;
      if (playerState.processingState == ProcessingState.completed) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.pause();
      }
    });
    _audioPlayer.setFilePath(widget.filepath);

    final RecordingDraftHandoff? persistedDraft = widget.persistedDraft;
    recording = persistedDraft?.recording ??
        Recording(
          createdAt: widget.recordingParts.isNotEmpty
              ? widget.recordingParts.first.startTime ?? widget.startTime
              : widget.startTime,
          mail: "",
          estimatedBirdsCount: _strnadiCountController.toInt(),
          device: "",
          byApp: true,
          note: _commentController.text,
          path: widget.filepath,
          partCount: widget.recordingParts.length,
          env: Config.hostEnvironment.name.toString(),
          totalSeconds: 0,
        );
    _recordingId = persistedDraft?.recording.id;

    // The durable insert already captured and validated the owner snapshot.
    // Loading it again from independently changing secure-storage keys could
    // accidentally rebind the draft while the form is open.
    _recordingOwnerReady =
        persistedDraft == null ? _loadRecordingOwner() : Future<void>.value();

    _deviceModelFuture = getDeviceModel();
    _deviceModelFuture.then((model) {
      if (!mounted) return;
      setState(() {
        recording.device = model;
      });
      logger.i('Device set to ${recording.device}');
    });

    // Log how many parts we received from streamRec.
    logger.i(
        "RecordingForm: Received ${widget.recordingParts.length} recording parts from streamRec.");

    if (persistedDraft != null) {
      recordingParts.addAll(persistedDraft.recordingParts);
    } else {
      // Convert the passed parts for compatibility with older callers. New
      // recorder flows persist the aggregate before opening this form.
      for (RecordingPartUnready part in widget.recordingParts) {
        try {
          RecordingPart newPart = RecordingPart.fromUnready(part);
          recordingParts.add(newPart);
        } catch (e, stackTrace) {
          logger.e(
            "Error converting part: $e",
            error: e,
            stackTrace: stackTrace,
          );
          _recordingPartsConversionError = e;
          recordingParts.clear();
          break;
        }
      }

      // Assign the duration (in seconds) to each RecordingPart.
      for (int i = 0;
          i < recordingParts.length && i < widget.recordingPartsTimeList.length;
          i++) {
        recordingParts[i].length = widget.recordingPartsTimeList[i];
      }
    }

    _route.addAll(widget.route);

    final RecordingPart? firstRecordingPart =
        firstRecordingPartOrNull(recordingParts);
    if (firstRecordingPart != null) {
      reverseGeocode(
        firstRecordingPart.gpsLatitudeStart,
        firstRecordingPart.gpsLongitudeStart,
      );
    }
  }

  Future<void> _loadRecordingOwner() async {
    final ActivatedAuthSessionSnapshot? session =
        await activatedAuthSessions.capture();
    if (session?.verified != true) {
      if (mounted) {
        _showMessage(
          t('postRecordingForm.recordingForm.dialogs.error.login'),
        );
      }
      return;
    }

    recording.mail = session!.subject;
    logger.i('Recording owner loaded from the activated session.');
  }

  // Helper method to display a simple message dialog.
  Future<void> _showMessage(String message) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(t('dialogs.message')),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('auth.buttons.ok')),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmDiscard() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            t('postRecordingForm.recordingForm.dialogs.discard.title'),
          ),
          content: Text(
            t('postRecordingForm.recordingForm.dialogs.discard.message'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: Text(
                t('postRecordingForm.recordingForm.dialogs.discard.no'),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                t('postRecordingForm.recordingForm.dialogs.discard.yes'),
              ),
            ),
          ],
        );
      },
    );
  }

  Route<void> _recorderRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => const LiveRec(),
      settings: const RouteSettings(name: '/Recorder'),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  void _replaceWithRecorder() {
    Navigator.of(context).pushReplacement(_recorderRoute());
  }

  Future<void> _deleteUnpersistedRecordingFiles() async {
    // Once a draft exists, SQLite owns these paths and retry/offline flows need
    // them. An ambiguous transaction result also remains DB-owned until a
    // later reconciliation proves that the aggregate is absent.
    if (!canDeleteUnpersistedDraftFiles(
      hasPersistedId: _recordingId != null || recording.id != null,
      persistenceMayHaveCommitted: _draftPersistenceMayHaveCommitted,
    )) {
      return;
    }

    final Set<String> paths = <String>{
      if (widget.filepath.isNotEmpty) widget.filepath,
      ...widget.recordingParts
          .map((RecordingPartUnready part) => part.path)
          .whereType<String>()
          .where((String path) => path.isNotEmpty),
      ...recordingParts
          .map((RecordingPart part) => part.path)
          .whereType<String>()
          .where((String path) => path.isNotEmpty),
    };

    for (final String path in paths) {
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error, stackTrace) {
        logger.e(
          'Failed to delete a discarded temporary recording file.',
          error: error,
          stackTrace: stackTrace,
        );
        Sentry.captureException(error, stackTrace: stackTrace);
      }
    }
  }

  Future<void> _deleteDraftAndOwnedFiles() async {
    final RecordingDraftHandoff? persistedDraft = widget.persistedDraft;
    if (persistedDraft != null) {
      await persistedDraft.discard();
      _recordingId = null;
      recording.id = null;
      return;
    }

    final int? recordingId = _recordingId ?? recording.id;
    if (recordingId != null) {
      await DatabaseNew.deleteRecordingFromCache(recordingId);
      _recordingId = null;
      recording.id = null;
      return;
    }

    await _deleteUnpersistedRecordingFiles();
  }

  Future<void> _discardAndReturnToRecorder() async {
    if (_isLoading || _isDiscarding || !mounted) return;
    setState(() => _isDiscarding = true);
    bool leaving = false;
    try {
      final bool shouldDiscard = await _confirmDiscard() ?? false;
      if (!shouldDiscard) return;

      try {
        await _audioPlayer.stop();
      } catch (error, stackTrace) {
        logger.w(
          'Failed to stop playback before discarding the recording',
          error: error,
          stackTrace: stackTrace,
        );
      }
      try {
        await _deleteDraftAndOwnedFiles();
      } catch (error, stackTrace) {
        logger.e(
          'Failed to discard recording draft',
          error: error,
          stackTrace: stackTrace,
        );
        Sentry.captureException(error, stackTrace: stackTrace);
        if (mounted) {
          await _showMessage(
            t('postRecordingForm.recordingForm.dialogs.error.saveFailed'),
          );
        }
        return;
      }
      if (!mounted) return;
      leaving = true;
      _replaceWithRecorder();
    } finally {
      if (!leaving && mounted) {
        setState(() => _isDiscarding = false);
      }
    }
  }

  // Helper method to seek the audio player relative to current position.
  void seekRelative(int seconds) {
    final currentPos = _audioPlayer.position;
    _audioPlayer.seek(currentPos + Duration(seconds: seconds));
  }

  List<Dialect> _buildDialects() {
    return dialectSegments.map((DialectModel dialect) {
      final Duration startOffset = Duration(
        microseconds:
            (dialect.startTime * Duration.microsecondsPerSecond).round(),
      );
      final Duration endOffset = Duration(
        microseconds:
            (dialect.endTime * Duration.microsecondsPerSecond).round(),
      );
      return Dialect(
        id: null,
        BEID: null,
        recordingId: null,
        recordingBEID: null,
        userGuessDialect: dialect.type,
        adminDialect: null,
        startDate: recording.createdAt.add(startOffset),
        endDate: recording.createdAt.add(endOffset),
      );
    }).toList(growable: false);
  }

  void _showDialectSelectionDialog() {
    final position = currentPositionDuration.inMilliseconds / 1000.0;
    showDialog(
      // disable tap out hide
      barrierDismissible: false,
      context: context,
      builder: (context) => DialectSelectionDialog(
        currentPosition: position,
        duration: totalDuration.inSeconds.toDouble(),
        onDialectAdded: (dialect) {
          setState(() {
            if (dialect == null) return;
            dialectSegments.add(dialect);
          });
        },
      ),
    );
  }

  String? _buildRecordingNote() {
    final userComment = _commentController.text.trim();
    final List<String> manualDialectLines = dialectSegments.map((dialect) {
      final String? manualNote = dialect.note?.trim();
      if (manualNote != null && manualNote.isNotEmpty) {
        return '- ${dialect.label}: $manualNote';
      }
      return '- ${dialect.label}';
    }).toList();

    if (manualDialectLines.isEmpty) {
      return userComment.isEmpty ? null : userComment;
    }

    final String manualDialectBlock =
        '${t('postRecordingForm.addDialect.note.appendHeader')}\n${manualDialectLines.join('\n')}';

    if (userComment.isEmpty) return manualDialectBlock;
    return '$userComment\n\n$manualDialectBlock';
  }

  Widget _buildDialectSegment(DialectModel dialect) {
    final String? manualNote = dialect.note?.trim();
    final bool hasManualNote = manualNote != null && manualNote.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: dialect.color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Text(
                  dialect.label,
                  style: TextStyle(
                    fontSize: 14,
                    color: dialect.color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    dialectSegments.remove(dialect);
                  });
                },
                child: Icon(Icons.delete_outline,
                    color: Colors.red.shade300, size: 20),
              ),
            ],
          ),
          if (hasManualNote) ...[
            const SizedBox(height: 6),
            Text(
              manualNote,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

    logger.i('Reverse geocoding the captured recording location.');
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.mapsApiKey}',
      };
      final response = await http.get(url, headers: headers);
      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final results = data['items'];
        if (results is List && results.isNotEmpty) {
          logger.i('Reverse geocoding returned a location.');
          if (!mounted) return;
          setState(() {
            placeTitle = results[0]['name'];
          });
        }
      } else {
        logger.e(
            "Reverse geocode failed with status code ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: $e', stackTrace: stackTrace, error: e);
    }
  }

  Future<String> getDeviceModel() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return '${android.manufacturer} ${android.model}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        final String machine = ios.utsname.machine;
        return machine.isEmpty ? 'iOS' : machine;
      }
    } catch (_) {
      // Ignore and fall through to default
    }
    return Platform.operatingSystem;
  }

  void togglePlay() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> upload() async {
    logger.i(
        "Uploading recording. Estimated birds count: ${_strnadiCountController.toInt()}");
    recording.note = _buildRecordingNote();
    recording.name = _recordingNameController.text.isEmpty
        ? null
        : _recordingNameController.text;
    recording.downloaded = true;
    recording.estimatedBirdsCount = _strnadiCountController.toInt();
    recording.partCount = recordingParts.length;
    recording.totalSeconds = recordingParts.fold<double>(
      0,
      (double total, RecordingPart part) => total + (part.length ?? 0),
    );
    await Future.wait<void>(<Future<void>>[
      _recordingOwnerReady,
      _deviceModelFuture.then<void>((String model) {
        recording.device = model;
      }),
    ]);
    if (!mounted) return;

    if (_recordingPartsConversionError != null ||
        recordingParts.isEmpty ||
        recordingParts.length != widget.recordingParts.length) {
      _showMessage(
        t('postRecordingForm.recordingForm.dialogs.error.invalidParts'),
      );
      return;
    }

    final List<Dialect> dialects = _buildDialects();
    try {
      if (_recordingId == null) {
        _recordingId = await DatabaseNew.insertRecordingDraft(
          recording,
          recordingParts,
          dialects,
        );
        recording.id = _recordingId;
        _draftPersistenceMayHaveCommitted = false;
        logger.i(
          'Recording draft $_recordingId and ${recordingParts.length} parts '
          'were saved atomically.',
        );
      } else {
        final RecordingDraftHandoff? persistedDraft = widget.persistedDraft;
        if (persistedDraft != null) {
          await persistedDraft.updateMetadata(dialects);
        } else {
          await DatabaseNew.updateRecordingDraft(recording, dialects);
        }
        logger.i(
          'Recording draft $_recordingId metadata was updated atomically.',
        );
      }
    } catch (error, stackTrace) {
      if (error is RecordingDraftPersistenceException &&
          error.mayHaveCommitted) {
        _draftPersistenceMayHaveCommitted = true;
      }
      logger.e(
        'Failed to save recording draft',
        error: error,
        stackTrace: stackTrace,
      );
      Sentry.captureException(error, stackTrace: stackTrace);
      if (mounted) {
        _showMessage(
          t('postRecordingForm.recordingForm.dialogs.error.saveFailed'),
        );
      }
      return;
    }

    // Check connectivity and user preference before upload
    if (!await Config.hasBasicInternet) {
      if (!mounted) return;
      logger.w("No internet connection, saved offline");
      await _showMessage(t(
          "postRecordingForm.recordingForm.dialogs.error.noInternet.message"));
      if (!mounted) return;
      _replaceWithRecorder();
      return;
    }
    if (!await Config.canUpload) {
      if (!mounted) return;
      logger.w("Upload only allowed on Wi-Fi, saved offline");
      await _showMessage(
          t("postRecordingForm.recordingForm.dialogs.error.wifiOnly.message"));
      if (!mounted) return;
      _replaceWithRecorder();
      return;
    }

    final ActivatedAuthSessionSnapshot? uploadSession =
        await activatedAuthSessions.capture();
    if (uploadSession?.verified != true) {
      if (!context.mounted) return;
      logger.w("User is in guest mode");
      final BuildContext formContext = context;
      Dialogs.showCupertinoDialog(
        context: formContext,
        builder: (BuildContext dialogContext) {
          return Dialogs.CupertinoAlertDialog(
            title: Text(t('bottomBar.errors.guest_user')),
            content: Text(t('bottomBar.errors.guest_user_desc_rec')),
            actions: [
              Dialogs.CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () {
                  //navigate to login
                  Navigator.of(dialogContext).pop();
                  if (!formContext.mounted) return;
                  Navigator.pushReplacement(
                    formContext,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          Authorizator(),
                      settings: const RouteSettings(name: '/'),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                },
                child: Text(t('bottomBar.errors.navigate_to_login')),
              ),
            ],
          );
        },
      );
      return;
    }
    try {
      await DatabaseNew.sendRecordingBackground(_recordingId!);
    } catch (e, stackTrace) {
      logger.e("Error sending recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        _showMessage(
          t('postRecordingForm.recordingForm.dialogs.error.scheduleFailed'),
        );
      }
      return;
    }
    logger.i("Recording upload scheduled");
    if (!mounted) return;
    _replaceWithRecorder();
  }

  @override
  void dispose() {
    _recordingNameController.dispose();
    _commentController.dispose();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioPlayingSubscription?.cancel();
    _audioStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryRed = const Color(0xFFFF3B3B);
    final Color secondaryRed = const Color(0xFFFFEDED);
    final Color yellowishBlack = const Color(0xFF2D2B18);
    final Color yellow = const Color(0xFFFFD641);
    final RecordingPart? firstRecordingPart =
        firstRecordingPartOrNull(recordingParts);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (_isLoading) return; // block back while loading
        if (didPop) return;
        await _discardAndReturnToRecorder();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: Text(placeTitle),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: ElevatedButton(
                    onPressed: !_isLoading
                        ? () async {
                            final shouldSave = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(t(
                                      'postRecordingForm.addDialect.dialogs.confirmation.title')),
                                  content: Text(t(
                                      'postRecordingForm.recordingForm.dialogs.confirmation.message')),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: Text(t(
                                          'postRecordingForm.addDialect.dialogs.confirmation.no')),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: Text(t(
                                          'postRecordingForm.addDialect.dialogs.confirmation.yes')),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (shouldSave == true) {
                              await _withLoader(() async {
                                await upload();
                              });
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: yellow,
                      foregroundColor: yellowishBlack,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    child:
                        Text(t('postRecordingForm.recordingForm.buttons.save')),
                  ),
                ),
              ],
              leading: IconButton(
                icon: Image.asset('assets/icons/backButton.png',
                    width: 30, height: 30),
                onPressed: !_isLoading ? _discardAndReturnToRecorder : null,
              ),
            ),
            body: SingleChildScrollView(
              child: Center(
                child: Column(
                  children: [
                    // Duration / playback controls
                    Text(
                      _formatDuration(totalDuration),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10, size: 32),
                          onPressed:
                              !_isLoading ? () => seekRelative(-10) : null,
                        ),
                        IconButton(
                          icon: Icon(isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled),
                          iconSize: 72,
                          onPressed: !_isLoading ? togglePlay : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10, size: 32),
                          onPressed:
                              !_isLoading ? () => seekRelative(10) : null,
                        ),
                      ],
                    ),

                    // Add dialect button
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text(t(
                            'postRecordingForm.recordingForm.buttons.addDialect')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF7C0),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onPressed:
                            !_isLoading ? _showDialectSelectionDialog : null,
                      ),
                    ),

                    // Dialect list (if any)
                    if (dialectSegments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: dialectSegments
                              .map((d) => _buildDialectSegment(d))
                              .toList(),
                        ),
                      ),

                    const SizedBox(height: 50),

                    // Form
                    Form(
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Recording name
                            Text(t('postRecordingForm.recordingForm.fields.recordingName.name'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: TextFormField(
                                controller: _recordingNameController,
                                textAlign: TextAlign.start,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 12),
                                ),
                                keyboardType: TextInputType.text,
                                maxLength: 49,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return t(
                                        'postRecordingForm.recordingForm.fields.recordingName.error.empty');
                                  } else if (value.length > 49) {
                                    return t(
                                        'postRecordingForm.recordingForm.fields.recordingName.error.tooLong');
                                  }
                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Bird count
                            Text(t('postRecordingForm.recordingForm.fields.birdCount.name'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text(
                              t(
                                _strnadiCountController.toInt() == 1
                                    ? 'postRecordingForm.recordingForm.slider.oneBird'
                                    : _strnadiCountController.toInt() == 2
                                        ? 'postRecordingForm.recordingForm.slider.twoBirds'
                                        : 'postRecordingForm.recordingForm.slider.threeOrMoreBirds',
                              ),
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
                                onChanged: (value) => setState(
                                    () => _strnadiCountController = value),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Comment
                            Text(t('postRecordingForm.recordingForm.fields.comment.name'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: TextFormField(
                                controller: _commentController,
                                textAlign: TextAlign.start,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 12),
                                ),
                                keyboardType: TextInputType.multiline,
                                maxLines: null,
                                validator: (value) => (value == null ||
                                        value.isEmpty)
                                    ? t('postRecordingForm.recordingForm.fields.comment.error.empty')
                                    : null,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Map label
                            Text(t('recListItem.placeTitle'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(placeTitle),
                            if (firstRecordingPart != null)
                              Text(
                                '${firstRecordingPart.gpsLatitudeStart} '
                                '${firstRecordingPart.gpsLongitudeStart}',
                              )
                            else
                              Text(
                                t('postRecordingForm.recordingForm.dialogs.error.invalidParts'),
                              ),
                            const SizedBox(height: 5),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: SizedBox(
                                  height: 200,
                                  child: FutureBuilder<bool>(
                                    future: Config.hasBasicInternet,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                            child: CircularProgressIndicator());
                                      } else if (!snapshot.hasData ||
                                          snapshot.data == false) {
                                        return Container(
                                          color: Colors.grey.shade300,
                                          alignment: Alignment.center,
                                          child: Text(
                                            t('postRecordingForm.recordingForm.placeholders.noInternet'),
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black54),
                                          ),
                                        );
                                      } else if (_computedCenter.latitude !=
                                              0.0 &&
                                          _computedCenter.longitude != 0.0) {
                                        return FlutterMap(
                                          options: MapOptions(
                                            initialCenter: _computedCenter,
                                            initialZoom: _computedZoom,
                                            interactionOptions:
                                                InteractionOptions(
                                                    flags:
                                                        InteractiveFlag.none),
                                          ),
                                          mapController: _mapController,
                                          children: [
                                            TileLayer(
                                              urlTemplate:
                                                  'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                                              userAgentPackageName:
                                                  'cz.delta.strnadi',
                                            ),
                                            if (_route.isNotEmpty)
                                              PolylineLayer(
                                                polylines: [
                                                  Polyline(
                                                      points: List.from(_route),
                                                      strokeWidth: 4.0,
                                                      color: Colors.blue),
                                                ],
                                              ),
                                            MarkerLayer(
                                              markers:
                                                  recordingParts.map((part) {
                                                return Marker(
                                                  point: LatLng(
                                                    part.gpsLatitudeStart,
                                                    part.gpsLongitudeStart,
                                                  ),
                                                  child: const Icon(Icons.place,
                                                      color: Colors.red,
                                                      size: 30),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        );
                                      } else {
                                        return Container(
                                          color: Colors.grey.shade300,
                                          alignment: Alignment.center,
                                          child: Text(
                                            t('postRecordingForm.recordingForm.placeholders.noGpsPoints'),
                                            style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),

                            // Discard button
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: !_isLoading
                                      ? _discardAndReturnToRecorder
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: secondaryRed,
                                    foregroundColor: primaryRed,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  child: Text(t(
                                      'postRecordingForm.recordingForm.buttons.discard')),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Global loader overlay
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Computed getters inserted inside _RecordingFormState:
  LatLng get _computedCenter {
    if (_route.isEmpty) return LatLng(0.0, 0.0);
    double sumLat = 0;
    double sumLon = 0;
    for (LatLng p in _route) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    return LatLng(sumLat / _route.length, sumLon / _route.length);
  }

  double get _computedZoom {
    if (_route.isEmpty) return 13.0;
    double minLat = _route.first.latitude;
    double maxLat = _route.first.latitude;
    double minLon = _route.first.longitude;
    double maxLon = _route.first.longitude;
    for (LatLng p in _route) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    double latDiff = maxLat - minLat;
    double lonDiff = maxLon - minLon;
    double maxDiff = latDiff > lonDiff ? latDiff : lonDiff;
    double idealZoom = math.log(360 / maxDiff) / math.ln2;
    if (idealZoom < 10) idealZoom = 10;
    if (idealZoom > 16) idealZoom = 16;
    return idealZoom;
  }
}
