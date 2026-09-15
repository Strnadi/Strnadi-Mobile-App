import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'recording_dialect_entry.dart';

class RecordingDialectsSection extends StatelessWidget {
  const RecordingDialectsSection({
    super.key,
    required this.loading,
    required this.error,
    required this.entries,
  });

  final bool loading;
  final String? error;
  final List<RecordingDialectEntry> entries;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      border: Border.all(color: Colors.grey),
      borderRadius: BorderRadius.circular(10),
    );
    const titleStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 14);

    if (loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Row(
          children: [
            Expanded(child: Text(t('dialectBadge.title'), style: titleStyle)),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('dialectBadge.title'), style: titleStyle),
            const SizedBox(height: 6),
            Text(
              t('map.dialogs.error.title'),
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('dialectBadge.title'), style: titleStyle),
            const SizedBox(height: 6),
            Text(
              t('dialectKeywords.unknown'),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10.0),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('dialectBadge.title'), style: titleStyle),
          const SizedBox(height: 8),
          for (final entry in entries) _buildDialectTile(entry),
        ],
      ),
    );
  }

  Widget _buildDialectTile(RecordingDialectEntry entry) {
    final Color baseColor = entry.color;
    final Color borderColor = entry.isRepresentant
        ? baseColor
        : Colors.grey.shade400;
    final Color background = baseColor.withOpacity(0.12);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
          color: borderColor,
          width: entry.isRepresentant ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (entry.isRepresentant)
                      Icon(Icons.star_rounded, size: 16, color: baseColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeRange(entry.startOffset, entry.endOffset),
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeRange(Duration start, Duration end) {
    final String startText = _formatDurationLabel(start);
    final String endText = _formatDurationLabel(end);
    if (startText == endText) {
      return startText;
    }
    return '$startText - $endText';
  }

  String _formatDurationLabel(Duration value) {
    if (value <= Duration.zero) {
      return '0:00';
    }
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds ~/ 60) % 60;
    final int seconds = totalSeconds % 60;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    final int totalMinutes = totalSeconds ~/ 60;
    return '${totalMinutes}:${twoDigits(seconds)}';
  }
}
