import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';

class RecordingDownloadCard extends StatelessWidget {
  const RecordingDownloadCard({
    super.key,
    required this.accessResolved,
    required this.canPlay,
    required this.downloaded,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
  });

  final bool accessResolved;
  final bool canPlay;
  final bool downloaded;
  final bool downloading;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => !accessResolved
      ? const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        )
      : !canPlay
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.25),
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 34),
                const SizedBox(height: 8),
                Text(
                  t('recordingPage.status.playRestricted'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        )
      : downloaded
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(14.0),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    Theme.of(context).colorScheme.secondary.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 34),
                  const SizedBox(height: 8),
                  Text(
                    t('recordingPage.status.notDownloaded'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('recListItem.noRecording'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (downloading) ...[
                    SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${(progress * 100).toStringAsFixed(1)}%'),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onCancel,
                      child: Text(t('recListItem.buttons.cancel')),
                    ),
                  ] else
                    ElevatedButton.icon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.download),
                      label: Text(t('recListItem.buttons.download')),
                    ),
                ],
              ),
            ),
          ),
        );
}
