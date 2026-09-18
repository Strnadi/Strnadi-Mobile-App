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
import 'package:record/record.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/guide_shortcut_button.dart';
import 'package:strnadi/navigation/notification_bell_button.dart';
import 'package:strnadi/navigation/scaffold_with_bottom_bar.dart';

/// Presentation only; capture, persistence and platform work belong to the session.
class RecordingView extends StatelessWidget {
  const RecordingView({
    super.key,
    required this.duration,
    required this.recordState,
    required this.hasMicPermission,
    required this.isGuestUser,
    required this.isProcessing,
    required this.isFinishing,
    required this.isDiscarding,
    required this.onToggle,
    required this.onFinish,
    required this.onDiscard,
    required this.confirmExit,
  });

  final Duration duration;
  final RecordState recordState;
  final bool hasMicPermission,
      isGuestUser,
      isProcessing,
      isFinishing,
      isDiscarding;
  final Future<void> Function() onToggle, onFinish, onDiscard;
  final Future<bool> Function() confirmExit;

  @override
  Widget build(BuildContext context) {
    final totalTime = duration;

    // Define custom colors to match your design.
    final Color primaryRed = const Color(0xFFFF3B3B);
    final Color secondaryRed = const Color(0xFFFFEDED);

    // Determine button colors, border, and shadow based on recording state.
    IconData iconData = Icons.mic;
    Color fillColor = primaryRed;
    Color iconColor = Colors.white;
    Border? border;
    List<BoxShadow> boxShadows = [];

    if (recordState == RecordState.stop) {
      // Stop state: filled red circle with white mic icon.
      iconData = Icons.mic;
      fillColor = primaryRed;
      iconColor = Colors.white;
      border = null;
      boxShadows = [];
    } else if (recordState == RecordState.record) {
      // Recording (pause button visible): white circle, thicker red border, red icon + glow.
      iconData = Icons.pause;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withValues(alpha: 0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    } else if (recordState == RecordState.pause) {
      // Paused (play button visible): white circle, thicker red border, red icon + glow.
      iconData = Icons.play_arrow;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withValues(alpha: 0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    }

    // Create the scaffold widget.
    final scaffoldWidget = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GuideShortcutButton(recorderExitPolicy: confirmExit),
        actions: [
          NotificationBellButton(
            isGuestUser: isGuestUser,
            recorderExitPolicy: confirmExit,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(top: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image banner at top
            LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final imageHeight = screenHeight * 0.25;
                return SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.0),
                      child: Image.asset(
                        'assets/images/bird_example.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // Recording button with vertical padding.
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Opacity(
                opacity: hasMicPermission ? 1.0 : 0.5,
                child: AbsorbPointer(
                  absorbing: isProcessing,
                  child: Semantics(
                    label: recordState == RecordState.stop
                        ? t('streamRec.buttons.startRecording')
                        : recordState == RecordState.record
                        ? t('streamRec.buttons.pauseRecording')
                        : t('streamRec.buttons.resumeRecording'),
                    button: true,
                    child: GestureDetector(
                      onTap: onToggle,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fillColor,
                          border: border,
                          boxShadow: boxShadows,
                        ),
                        child: recordState == RecordState.pause
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.play_arrow,
                                    size: 40,
                                    color: iconColor,
                                  ),
                                  Icon(Icons.mic, size: 20, color: iconColor),
                                ],
                              )
                            : Icon(iconData, color: iconColor, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Timer display
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: recordState == RecordState.record
                      ? primaryRed
                      : Colors.grey,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                _formatTime(totalTime),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Status text
            if (recordState == RecordState.stop) ...[
              Text(
                t('streamRec.status.stopped'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ] else if (recordState == RecordState.record) ...[
              Text(
                t('streamRec.status.recording'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ] else if (recordState == RecordState.pause) ...[
              Text(
                t('streamRec.status.paused'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Finish button
            if (recordState == RecordState.record ||
                recordState == RecordState.pause)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isFinishing || isDiscarding || isProcessing
                        ? null
                        : onFinish,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: secondaryRed,
                      foregroundColor: primaryRed,
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Bricolage Grotesque',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop, color: primaryRed),
                        const SizedBox(width: 8),
                        Text(
                          t('streamRec.buttons.finishRecording'),
                          style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Discard button
            if (recordState == RecordState.record ||
                recordState == RecordState.pause)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 3,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isFinishing || isDiscarding || isProcessing
                        ? null
                        : onDiscard,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Bricolage Grotesque',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          t('streamRec.buttons.discardRecording'),
                          style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: ReusableBottomAppBar(
        currentPage: BottomBarItem.recorder,
        changeConfirmation: confirmExit,
        isGuestUser: isGuestUser,
      ),
    );
    // Return the PopScope widget with an onPopInvokedWithResult callback that completes without returning any widget.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await onDiscard();
      },
      child: scaffoldWidget,
    );
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final hundredths = ((duration.inMilliseconds % 1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds,$hundredths';
  }
}
