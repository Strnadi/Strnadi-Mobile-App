import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/userData.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/recording_detail/recording_audio_player.dart';
import 'package:strnadi/map/recording_detail/recording_detail_controller.dart';
import 'package:strnadi/map/recording_detail/recording_detail_repository.dart';
import 'package:strnadi/map/recording_detail/recording_dialects_section.dart';
import 'package:strnadi/map/recording_detail/recording_download_card.dart';
import 'package:strnadi/map/recording_detail/recording_location_preview.dart';
import 'package:strnadi/map/recording_detail/recording_metadata.dart';
import 'package:strnadi/map/recording_detail/recording_playback_controls.dart';
import 'package:strnadi/navigation/scaffold_with_bottom_bar.dart';

class RecordingFromMap extends StatefulWidget {
  const RecordingFromMap({
    super.key,
    required this.recording,
    required this.user,
    this.repository = const DatabaseRecordingDetailRepository(),
    this.audioFactory,
  });

  final Recording recording;
  final UserData? user;
  final RecordingDetailRepository repository;
  final RecordingAudioPlayer Function()? audioFactory;

  @override
  State<RecordingFromMap> createState() => _RecordingFromMapState();
}

class _RecordingFromMapState extends State<RecordingFromMap> {
  late RecordingDetailController _controller;

  void _createController() {
    _controller = RecordingDetailController(
      recording: widget.recording,
      repository: widget.repository,
      audio: widget.audioFactory?.call() ?? JustAudioRecordingPlayer(),
    );
    unawaited(_controller.initialize());
  }

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(covariant RecordingFromMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recording, widget.recording)) {
      _controller.dispose();
      _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAction(
    Future<RecordingDetailActionResult> action, {
    bool download = false,
  }) async {
    final result = await action;
    if (!mounted) return;
    if (download && result == RecordingDetailActionResult.unavailable) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('recListItem.errors.errorDownloading')),
          content: Text(t('recordingPage.status.errorDownloading')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('auth.buttons.ok')),
            ),
          ],
        ),
      );
      return;
    }
    final key = switch (result) {
      RecordingDetailActionResult.success ||
      RecordingDetailActionResult.stale => null,
      RecordingDetailActionResult.restricted =>
        'recordingPage.status.playRestricted',
      RecordingDetailActionResult.canceled =>
        'recordingPage.status.downloadCanceled',
      RecordingDetailActionResult.unavailable =>
        'recordingPage.status.errorDownloading',
    };
    if (key != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t(key))));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final detail = _controller;
      final recording = detail.recording;
      if (!detail.isDownloading &&
          !detail.loaded &&
          recording.path?.isNotEmpty == true) {
        return ScaffoldWithBottomBar(
          selectedPage: BottomBarItem.list,
          appBarTitle: detail.title,
          content: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(detail.title),
          leading: GlassIconButton(
            nativeSymbol: 'chevron.left',
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Image.asset(
              'assets/icons/backButton.png',
              width: 30,
              height: 30,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: detail.refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                RecordingDownloadCard(
                  accessResolved: detail.playAccessResolved,
                  canPlay: detail.canAccessPlayback,
                  downloaded: recording.downloaded,
                  downloading: detail.isDownloading,
                  progress: detail.downloadProgress,
                  onDownload: () =>
                      _handleAction(detail.download(), download: true),
                  onCancel: detail.cancelDownload,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      if (recording.downloaded && detail.canAccessPlayback)
                        RecordingPlaybackControls(
                          position: detail.playbackPosition,
                          duration: detail.playbackDuration,
                          progress: detail.playbackProgress,
                          isPlaying: detail.isPlaying,
                          onTogglePlay: () =>
                              _handleAction(detail.togglePlay()),
                          onSeek: detail.seekRelative,
                        ),
                      RecordingMetadata(
                        recording: recording,
                        user: widget.user,
                        dialects: RecordingDialectsSection(
                          loading: detail.dialectsLoading,
                          error: detail.dialectsError,
                          entries: detail.dialectEntries,
                        ),
                      ),
                    ],
                  ),
                ),
                if (detail.parts.isNotEmpty)
                  RecordingLocationPreview(
                    position: LatLng(
                      detail.parts.first.gpsLatitudeStart,
                      detail.parts.first.gpsLongitudeStart,
                    ),
                    placeTitle: detail.placeTitle,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
