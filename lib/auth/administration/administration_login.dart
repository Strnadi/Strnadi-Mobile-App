import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/session_navigation.dart';
import 'app_administration.dart';
import 'pkce_attempt.dart';

class AdministrationLogin extends StatefulWidget {
  const AdministrationLogin({super.key, this.signIn});
  final Future<void> Function()? signIn;
  @override
  State<AdministrationLogin> createState() => _AdministrationLoginState();
}

class _AdministrationLoginState extends State<AdministrationLogin> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _signIn();
    });
  }

  @override
  void dispose() {
    if (_busy && widget.signIn == null && AppAdministration.enabled) {
      AppAdministration.session.cancelSignIn();
    }
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.signIn ?? AppAdministration.signIn)();
      if (mounted) await navigateToSessionLanding(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is OAuthFailure
              ? error.translationKey
              : 'auth.administration.errors.server',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      title: Text(t('auth.buttons.login')),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t('auth.administration.description'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null) Text(t(_error!), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_error != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD641),
                  foregroundColor: const Color(0xFF2D2B18),
                ),
                onPressed: _busy ? null : _signIn,
                child: Text(t('auth.administration.continue')),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    ),
  );
}
