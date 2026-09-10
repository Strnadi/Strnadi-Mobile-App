import 'package:flutter/material.dart';
import 'package:strnadi/config/host_environment.dart';
import 'package:strnadi/localization/localization.dart';

class EnvironmentBanner extends StatelessWidget {
  const EnvironmentBanner(
      {super.key, required this.environment, required this.child});

  final HostEnvironment environment;
  final Widget child;

  @override
  Widget build(BuildContext context) => environment.isNonProduction
      ? Banner(
          message: t(environment.badgeKey),
          location: BannerLocation.topEnd,
          color: Colors.deepOrange,
          child: child,
        )
      : child;
}
