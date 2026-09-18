import 'package:strnadi/projects/project_selector.dart';
import 'package:strnadi/projects/available_project.dart';
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
      if (widget.signIn != null) {
        await widget.signIn!();
      } else {
        await AppAdministration.signIn(
          chooseProject: (projects) async {
            if (!mounted) throw const OAuthFailure(OAuthFailureKind.cancelled);
            AvailableProject? choice;
            final selected = await Navigator.of(context).push<AvailableProject>(
              MaterialPageRoute(
                builder: (selectorContext) => ProjectSelector(
                  activeId: '',
                  allowBrowsing: false,
                  load: () async => projects,
                  select: (project) async => choice = project,
                  onSelected: () => Navigator.of(selectorContext).pop(choice),
                ),
              ),
            );
            if (selected == null) {
              throw const OAuthFailure(OAuthFailureKind.cancelled);
            }
            return selected;
          },
          chooseFirstProject: (projects, join) async {
            if (!mounted) throw const OAuthFailure(OAuthFailureKind.cancelled);
            final selected = await Navigator.of(context).push<AvailableProject>(
              MaterialPageRoute(
                builder: (selectorContext) => ProjectSelector(
                  activeId: '',
                  load: () async => [],
                  loadCatalog: () async => projects,
                  browseInitially: true,
                  join: join,
                  onJoined: (project) =>
                      Navigator.of(selectorContext).pop(project),
                ),
              ),
            );
            if (selected == null) {
              throw const OAuthFailure(OAuthFailureKind.cancelled);
            }
            return selected;
          },
        );
      }
      if (mounted) await navigateToSessionLanding(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is OAuthFailure
              ? error.translationKey
              : error is StateError && error.message == 'projects.empty'
              ? 'projects.empty'
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
