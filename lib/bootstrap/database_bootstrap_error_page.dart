import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';

typedef DatabaseBootstrapRetry = Future<void> Function();
typedef DatabaseBootstrapRetryFailure = void Function(
  Object error,
  StackTrace stackTrace,
);

class DatabaseBootstrapErrorApp extends StatelessWidget {
  const DatabaseBootstrapErrorApp({
    required this.onRetry,
    this.onRetryFailure,
    super.key,
  });

  final DatabaseBootstrapRetry onRetry;
  final DatabaseBootstrapRetryFailure? onRetryFailure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Strnadi',
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: DatabaseBootstrapErrorPage(
        onRetry: onRetry,
        onRetryFailure: onRetryFailure,
      ),
    );
  }
}

class DatabaseBootstrapErrorPage extends StatefulWidget {
  const DatabaseBootstrapErrorPage({
    required this.onRetry,
    this.onRetryFailure,
    this.title,
    this.message,
    this.retryLabel,
    super.key,
  });

  final DatabaseBootstrapRetry onRetry;
  final DatabaseBootstrapRetryFailure? onRetryFailure;
  final String? title;
  final String? message;
  final String? retryLabel;

  @override
  State<DatabaseBootstrapErrorPage> createState() =>
      _DatabaseBootstrapErrorPageState();
}

class _DatabaseBootstrapErrorPageState
    extends State<DatabaseBootstrapErrorPage> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } catch (error, stackTrace) {
      widget.onRetryFailure?.call(error, stackTrace);
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.title ?? t('bootstrap.databaseError.title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.message ?? t('bootstrap.databaseError.message'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _retrying ? null : _retry,
                    child: _retrying
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.retryLabel ??
                                t('bootstrap.databaseError.retry'),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
