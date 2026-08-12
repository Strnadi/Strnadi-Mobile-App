import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/upload_integration_helpers.dart';
import 'package:strnadi/localization/localization.dart';

class IncompleteUploadPrompt {
  IncompleteUploadPrompt._();

  static bool _showing = false;
  static final Set<int> _promptedRecordingIds = <int>{};

  static Future<void> checkAndPrompt(
    BuildContext context, {
    int? recordingId,
    bool oncePerSession = true,
  }) async {
    if (_showing) return;

    // Claim the prompt before the asynchronous lookup. Multiple screens can
    // request the check in the same frame and must not race into two dialogs.
    _showing = true;
    try {
      final List<IncompleteRecordingUpload> issues =
          await DatabaseNew.findIncompleteUploads(recordingId: recordingId);
      if (!context.mounted || issues.isEmpty) return;

      final List<IncompleteRecordingUpload> visibleIssues = oncePerSession
          ? issues
              .where((IncompleteRecordingUpload issue) =>
                  issue.recording.id == null ||
                  !_promptedRecordingIds.contains(issue.recording.id))
              .toList(growable: false)
          : issues;
      if (visibleIssues.isEmpty) return;

      final bool canSend = visibleIssues.any(
        (IncompleteRecordingUpload issue) => issue.canResend,
      );
      final bool? shouldSend = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(t('recordingUploadCheck.title')),
          content: Text(_buildMessage(visibleIssues, canSend: canSend)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t(canSend
                  ? 'recordingUploadCheck.actions.later'
                  : 'auth.buttons.ok')),
            ),
            if (canSend)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(t('recordingUploadCheck.actions.send')),
              ),
          ],
        ),
      );

      for (final IncompleteRecordingUpload issue in visibleIssues) {
        final int? id = issue.recording.id;
        if (id != null) {
          _promptedRecordingIds.add(id);
        }
      }

      if (shouldSend == true && context.mounted) {
        await _sendMissingAudio(context, visibleIssues);
      }
    } catch (error, stackTrace) {
      // This check runs from post-frame callbacks as well as explicit actions.
      // A DB inspection failure must not become an unhandled framework error.
      Sentry.captureException(error, stackTrace: stackTrace);
    } finally {
      _showing = false;
    }
  }

  static String _buildMessage(
    List<IncompleteRecordingUpload> issues, {
    required bool canSend,
  }) {
    final String details = issues.length == 1
        ? _singleIssueMessage(issues.first)
        : _multipleIssuesMessage(issues);
    final String nextStep = canSend
        ? t('recordingUploadCheck.messages.canSend')
        : t('recordingUploadCheck.messages.cannotSend');
    return '$details\n\n$nextStep';
  }

  static String _singleIssueMessage(IncompleteRecordingUpload issue) {
    final String name = issue.recording.name?.trim() ?? '';
    final bool canShowExactCounts = backendMissingPartCountsAreDisplayable(
      hasExactBackendPartCounts: issue.hasExactBackendPartCounts,
      expectedPartsCount: issue.expectedPartsCount,
      uploadedPartsCount: issue.uploadedPartsCount,
    );
    if (!canShowExactCounts) {
      final String key = name.isEmpty
          ? 'recordingUploadCheck.messages.singleUnknown'
          : 'recordingUploadCheck.messages.singleNamedUnknown';
      return _format(t(key), <String, String>{'name': name});
    }
    final String key = name.isEmpty
        ? 'recordingUploadCheck.messages.single'
        : 'recordingUploadCheck.messages.singleNamed';
    return _format(t(key), <String, String>{
      'name': name,
      'uploaded': issue.uploadedPartsCount.toString(),
      'expected': issue.expectedPartsCount.toString(),
      'missing': issue.missingPartsCount.toString(),
    });
  }

  static String _multipleIssuesMessage(List<IncompleteRecordingUpload> issues) {
    final bool canShowExactCounts = issues.every(
      (IncompleteRecordingUpload issue) =>
          backendMissingPartCountsAreDisplayable(
        hasExactBackendPartCounts: issue.hasExactBackendPartCounts,
        expectedPartsCount: issue.expectedPartsCount,
        uploadedPartsCount: issue.uploadedPartsCount,
      ),
    );
    if (!canShowExactCounts) {
      return _format(
        t('recordingUploadCheck.messages.multipleUnknown'),
        <String, String>{'count': issues.length.toString()},
      );
    }
    final int missing = issues.fold<int>(
      0,
      (int sum, IncompleteRecordingUpload issue) =>
          sum + issue.missingPartsCount,
    );
    return _format(
        t('recordingUploadCheck.messages.multiple'), <String, String>{
      'count': issues.length.toString(),
      'missing': missing.toString(),
    });
  }

  static Future<void> _sendMissingAudio(
    BuildContext context,
    List<IncompleteRecordingUpload> issues,
  ) async {
    final List<IncompleteRecordingUpload> resendableIssues = issues
        .where((IncompleteRecordingUpload issue) =>
            issue.canResend && issue.recording.id != null)
        .toList(growable: false);
    final int skippedCount = issues.length - resendableIssues.length;

    if (resendableIssues.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('recordingUploadCheck.messages.sendFailed'))),
      );
      return;
    }

    final BestEffortBatchResult<IncompleteRecordingUpload> result =
        await runBestEffortBatch<IncompleteRecordingUpload>(
      resendableIssues,
      (IncompleteRecordingUpload issue) {
        return issue.resendMissingParts();
      },
    );
    for (final BestEffortBatchFailure<IncompleteRecordingUpload> failure
        in result.failures) {
      Sentry.captureException(
        failure.error,
        stackTrace: failure.stackTrace,
      );
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.succeeded
              ? skippedCount == 0
                  ? t('recordingUploadCheck.messages.sent')
                  : _format(
                      t('recordingUploadCheck.messages.sentWithSkipped'),
                      <String, String>{'count': skippedCount.toString()},
                    )
              : t('recordingUploadCheck.messages.sendFailed'),
        ),
      ),
    );
  }

  static String _format(String value, Map<String, String> replacements) {
    String result = value;
    replacements.forEach((String key, String replacement) {
      result = result.replaceAll('{$key}', replacement);
    });
    return result;
  }
}
