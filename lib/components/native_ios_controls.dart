import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get usesNativeIOSControls =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Hosts UIKit controls; UIKit owns material, motion and transparency settings.
class NativeIOSControl extends StatefulWidget {
  const NativeIOSControl({
    super.key,
    required this.configuration,
    required this.onAction,
  });

  final Map<String, Object?> configuration;
  final Future<void> Function(int index) onAction;

  @override
  State<NativeIOSControl> createState() => _NativeIOSControlState();
}

class _NativeIOSControlState extends State<NativeIOSControl> {
  MethodChannel? _channel;
  bool _handlingAction = false;

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method != 'activate' || _handlingAction || !mounted) return null;
    final index = call.arguments;
    if (index is! int) return null;
    _handlingAction = true;
    try {
      await widget.onAction(index);
      // Wait for setState or a zero-duration route replacement to commit before
      // reconciling UIKit. Otherwise an approved tap briefly snaps back.
      if (mounted) await WidgetsBinding.instance.endOfFrame;
      return mounted ? widget.configuration : null;
    } finally {
      _handlingAction = false;
    }
  }

  void _created(int id) {
    if (!mounted) return;
    _channel = MethodChannel('com.delta.strnadi/native-controls/$id')
      ..setMethodCallHandler(_handleCall);
    _update();
  }

  Future<void> _update() async {
    try {
      await _channel?.invokeMethod<void>('update', widget.configuration);
    } on MissingPluginException {
      // The platform view can disappear while a route is being replaced.
    }
  }

  @override
  void didUpdateWidget(covariant NativeIOSControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: 'com.delta.strnadi/native-controls',
    creationParams: widget.configuration,
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _created,
  );
}

class NativeIOSTabBar extends StatelessWidget {
  const NativeIOSTabBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<String> labels;
  final int selectedIndex;
  final Future<void> Function(int index) onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80 + MediaQuery.viewPaddingOf(context).bottom,
    child: NativeIOSControl(
      configuration: {
        'kind': 'tabs',
        'labels': labels,
        'symbols': const [
          'map',
          'list.bullet',
          'mic',
          'book',
          'person.crop.circle',
        ],
        'selectedIndex': selectedIndex,
      },
      onAction: onTap,
    ),
  );
}
