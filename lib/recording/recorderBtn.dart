import 'package:flutter/material.dart';

class CustomRecordingButton extends StatelessWidget {
  const CustomRecordingButton({
    super.key,
    required this.isRecording,
    required this.onPressed,
    required this.finished_recordings,
  });

  final bool isRecording;
  final VoidCallback onPressed;
  final bool finished_recordings;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      height: 100,
      width: 100,
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.all(
        isRecording ? 25 : 15,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: finished_recordings ? Colors.green : Colors.red,
          width: isRecording ? 8 : 3,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          color: finished_recordings ? Colors.green : Colors.red,
          shape: isRecording ? BoxShape.rectangle : BoxShape.circle,
        ),
        child: MaterialButton(
          onPressed: onPressed,
          shape: const CircleBorder(),
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }


}