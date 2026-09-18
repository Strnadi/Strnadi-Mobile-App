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
import '../platform/recording_foreground_service.dart';
import '../session/recording_controller.dart';
import '../widgets/recording_view.dart';

class LiveRec extends StatefulWidget {
  const LiveRec({super.key, this.foregroundService});

  final RecordingForegroundService? foregroundService;

  @override
  State<LiveRec> createState() => _LiveRecState();
}

class _LiveRecState extends State<LiveRec> {
  late final RecordingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RecordingController(
      contextProvider: () => context,
      foregroundService: widget.foregroundService,
    )..initialize();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, child) => RecordingView(
      duration: _controller.duration,
      recordState: _controller.recordState,
      hasMicPermission: _controller.hasMicPermission,
      isGuestUser: _controller.isGuestUser,
      isProcessing: _controller.isProcessing,
      isFinishing: _controller.isFinishing,
      isDiscarding: _controller.isDiscarding,
      onToggle: _controller.toggleRecording,
      onFinish: _controller.finishRecording,
      onDiscard: _controller.discardRecording,
      confirmExit: _controller.confirmExit,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
