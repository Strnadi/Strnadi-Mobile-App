/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
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
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/guide_page.dart';
import 'package:strnadi/navigation/recorder_exit_policy.dart';

typedef GuidePageBuilder = Widget Function(BuildContext context);

Future<void> openGuideScreen(
  BuildContext context, {
  RecorderExitPolicy? recorderExitPolicy,
  GuidePageBuilder? guidePageBuilder,
}) async {
  if (ModalRoute.of(context)?.settings.name == '/guide') {
    return;
  }
  if (!await permitsRecorderExit(recorderExitPolicy)) return;
  if (!context.mounted) return;

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: guidePageBuilder ?? (_) => const GuidePage(),
      settings: const RouteSettings(name: '/guide'),
    ),
  );
}

class GuideShortcutButton extends StatelessWidget {
  final RecorderExitPolicy? recorderExitPolicy;
  final GuidePageBuilder? guidePageBuilder;

  const GuideShortcutButton({
    super.key,
    this.recorderExitPolicy,
    this.guidePageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t('user.menu.items.guide'),
      icon: const Icon(Icons.help_outline),
      onPressed: () => openGuideScreen(
        context,
        recorderExitPolicy: recorderExitPolicy,
        guidePageBuilder: guidePageBuilder,
      ),
    );
  }
}
