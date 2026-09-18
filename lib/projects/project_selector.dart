import 'package:strnadi/projects/project_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/auth/administration/app_administration.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/recording/screens/recording_screen.dart';
import 'available_project.dart';
import 'project_switch_guard.dart';

class ProjectSelector extends StatefulWidget {
  const ProjectSelector({
    super.key,
    this.load,
    this.select,
    this.activeId,
    this.onSelected,
    this.loadCatalog,
    this.join,
    this.onJoined,
    this.browseInitially = false,
    this.allowBrowsing = true,
  });
  final Future<List<AvailableProject>> Function()? load;
  final Future<void> Function(AvailableProject)? select;
  final String? activeId;
  final VoidCallback? onSelected;
  final Future<List<AvailableProject>> Function()? loadCatalog;
  final Future<void> Function(AvailableProject)? join;
  final ValueChanged<AvailableProject>? onJoined;
  final bool browseInitially;
  final bool allowBrowsing;

  @override
  State<ProjectSelector> createState() => _ProjectSelectorState();
}

class _ProjectSelectorState extends State<ProjectSelector> {
  List<AvailableProject>? _projects;
  String? _error;
  bool _busy = false;
  AvailableProject? _retry;
  List<AvailableProject>? _catalog;
  bool _retryJoin = false;
  bool _retryCatalog = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    ProjectDiagnostics.event(ProjectEvent.selectorOpened);
    _load().then((_) {
      if (mounted && widget.browseInitially) _browse();
    });
  }

  Future<void> _load() async {
    _retry = null;
    _retryCatalog = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final projects = await ProjectDiagnostics.run(
        ProjectOperation.loadSelector,
        () => (widget.load ?? AppAdministration.availableProjects)(),
      );
      if (mounted) setState(() => _projects = projects);
    } catch (_) {
      if (mounted) setState(() => _error = 'projects.loadFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browse() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = null;
      _retryCatalog = true;
    });
    try {
      final projects = await ProjectDiagnostics.run(
        ProjectOperation.browseSelector,
        () => (widget.loadCatalog ?? AppAdministration.projectCatalog)(),
      );
      if (mounted) setState(() => _catalog = projects);
    } catch (_) {
      if (mounted) setState(() => _error = 'projects.catalogFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(AvailableProject project) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _retry = project;
      _retryJoin = true;
    });
    try {
      await ProjectDiagnostics.run(
        ProjectOperation.joinSelector,
        () => (widget.join ?? AppAdministration.joinProject)(project),
      );
      if (!mounted) return;
      setState(() {
        _projects = [...?_projects?.where((p) => p.id != project.id), project];
        _notice = 'projects.joined';
        _retry = null;
      });
      widget.onJoined?.call(project);
    } catch (_) {
      if (mounted) setState(() => _error = 'projects.joinFailed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(AvailableProject project) async {
    if (_busy) return;
    if (ProjectSwitchGuard.recording) {
      ProjectDiagnostics.event(ProjectEvent.recordingBlocked);
      setState(() => _error = 'projects.recordingBlocked');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _retry = project;
      _retryJoin = false;
    });
    try {
      await ProjectDiagnostics.run(
        ProjectOperation.switchSelector,
        () => (widget.select ?? AppAdministration.switchProject)(project),
      );
      if (!mounted) return;
      ProjectDiagnostics.event(ProjectEvent.selectorNavigation);
      if (widget.onSelected != null) {
        widget.onSelected!();
      } else {
        // A project switch must not run the login flow's guest-draft adoption.
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder<void>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, animation, secondaryAnimation) => const LiveRec(),
            settings: const RouteSettings(name: '/Recorder'),
          ),
          (_) => false,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is StateError &&
                  [
                    'projects.recordingBlocked',
                    'projects.revoked',
                    'projects.empty',
                  ].contains(error.message)
              ? error.message
              : 'projects.switchFailed',
        );
        if (_error == 'projects.revoked') _retry = null;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    ProjectDiagnostics.event(ProjectEvent.selectorClosed);
    super.dispose();
  }

  void _retryOperation() {
    ProjectDiagnostics.event(ProjectEvent.selectorRetry);
    if (_retry != null) {
      _retryJoin ? _join(_retry!) : _select(_retry!);
    } else {
      _retryCatalog ? _browse() : _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = widget.activeId ?? Config.administration?.projectId;
    final otherProjects = _catalog
        ?.where((p) => !(_projects ?? []).any((member) => member.id == p.id))
        .toList();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(t('projects.title'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(t('projects.loading')),
            ],
            if (_error != null) ...[
              Text(t(_error!)),
              TextButton(
                onPressed: _busy ? null : _retryOperation,
                child: Text(t('projects.retry')),
              ),
            ],
            if (_notice != null) Text(t(_notice!)),
            if (_projects?.isEmpty == true) Text(t('projects.empty')),
            for (final project in _projects ?? <AvailableProject>[])
              ListTile(
                title: Text(project.name),
                subtitle: Text(
                  t(
                    project.id == activeId
                        ? 'projects.active'
                        : project.apiOrigin == null
                        ? 'projects.unavailable'
                        : 'projects.select',
                  ),
                ),
                trailing: project.id == activeId
                    ? const Icon(Icons.check)
                    : null,
                enabled: !_busy && project.apiOrigin != null,
                onTap: () => _select(project),
              ),
            if (widget.allowBrowsing) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _browse,
                icon: const Icon(Icons.add),
                label: Text(t('projects.browse')),
              ),
            ],
            if (otherProjects != null) ...[
              const SizedBox(height: 16),
              Text(
                t('projects.otherProjects'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (otherProjects.isEmpty) Text(t('projects.noOtherProjects')),
              for (final project in otherProjects)
                ListTile(
                  title: Text(project.name),
                  subtitle: project.apiOrigin == null
                      ? Text(t('projects.unavailable'))
                      : null,
                  trailing: TextButton(
                    onPressed: _busy || project.apiOrigin == null
                        ? null
                        : () => _join(project),
                    child: Text(t('projects.join')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
