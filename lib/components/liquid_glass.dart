import 'dart:ui';

import 'package:flutter/material.dart';
import 'native_ios_controls.dart';

/// Flutter-rendered glass for the floating navigation and control layer.
/// High contrast and accessible navigation use an opaque, unblurred surface.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 28});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final opaque = media.highContrast || media.accessibleNavigation;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF242629) : const Color(0xFFF9FAF7);
    final borderRadius = BorderRadius.circular(radius);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: opaque ? 1 : .88),
            base.withValues(alpha: opaque ? 1 : .64),
          ],
        ),
        border: Border.all(
          color: (dark ? Colors.white38 : Colors.white).withValues(
            alpha: opaque ? 1 : .8,
          ),
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x180E201B),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: opaque
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: surface,
              ),
      ),
    );
  }
}

/// Matches 48-point controls with 4-point outer spacing in a 56-point toolbar.
const glassAppBarTheme = AppBarThemeData(
  leadingWidth: 72,
  actionsPadding: EdgeInsetsDirectional.only(end: 8),
);

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.nativeSymbol,
    this.hasBadge = false,
    this.padding = const EdgeInsets.all(4),
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? nativeSymbol;
  final bool hasBadge;

  /// External spacing. Use zero in map slots that already supply an 8-point gap.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: _buildControl(context));

  Widget _buildControl(BuildContext context) {
    if (usesNativeIOSControls && nativeSymbol != null) {
      return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: 48,
          height: 48,
          child: NativeIOSControl(
            configuration: {
              'kind': 'button',
              'symbol': nativeSymbol,
              'label': tooltip,
              'enabled': onPressed != null,
              'badge': hasBadge,
            },
            onAction: (_) async {
              onPressed?.call();
            },
          ),
        ),
      );
    }
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: LiquidGlass(
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            maximumSize: const Size(48, 48),
            padding: const EdgeInsets.all(12),
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF252D29),
            disabledForegroundColor: Colors.grey,
            shape: const CircleBorder(),
          ),
        ),
      ),
    );
  }
}

/// Floating capsule with room for the device's home indicator.
class GlassNavigationBar extends StatelessWidget {
  const GlassNavigationBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: LiquidGlass(
      radius: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [for (final child in children) Expanded(child: child)],
        ),
      ),
    ),
  );
}
