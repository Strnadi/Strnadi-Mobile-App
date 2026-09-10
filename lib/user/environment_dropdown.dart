import 'package:flutter/material.dart';
import 'package:strnadi/config/host_environment.dart';
import 'package:strnadi/localization/localization.dart';

class EnvironmentDropdown extends StatelessWidget {
  const EnvironmentDropdown({
    super.key,
    required this.environment,
    required this.onChanged,
  });

  final HostEnvironment environment;
  final ValueChanged<HostEnvironment?>? onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: t('user.settings.environment.label'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<HostEnvironment>(
            value: environment,
            isExpanded: true,
            isDense: true,
            items: [
              for (final value in HostEnvironment.values)
                DropdownMenuItem(value: value, child: Text(t(value.labelKey))),
            ],
            onChanged: onChanged,
          ),
        ),
      );
}

/// Testers/admins can opt in; a non-production session can always get back out.
bool canEditEnvironment(String? role, HostEnvironment environment) =>
    role == 'admin' || role == 'tester' || environment.isNonProduction;

Future<bool> confirmEnvironmentChange(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(t('user.settings.environment.confirmTitle')),
        content: Text(t('user.settings.environment.confirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t('user.settings.environment.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t('user.settings.environment.continue')),
          ),
        ],
      ),
    ) ??
    false;
