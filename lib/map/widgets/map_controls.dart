import 'package:flutter/material.dart';
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/localization/localization.dart';

class MapSearchToolbar extends StatelessWidget {
  const MapSearchToolbar({
    super.key,
    required this.search,
    required this.onLegend,
  });

  final Widget search;
  final VoidCallback onLegend;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox.square(
        dimension: 48,
        child: GlassIconButton(
          padding: EdgeInsets.zero,
          nativeSymbol: 'info',
          onPressed: onLegend,
          tooltip: t('map.buttons.info'),
          icon: Image.asset('assets/icons/info.png', width: 30, height: 30),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: search),
    ],
  );
}

class MapActionButtons extends StatelessWidget {
  const MapActionButtons({
    super.key,
    required this.onFilters,
    required this.onLocate,
  });

  final VoidCallback onFilters;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 48,
        child: GlassIconButton(
          padding: EdgeInsets.zero,
          nativeSymbol: 'slider.horizontal.3',
          onPressed: onFilters,
          tooltip: t('map.buttons.mapSettings'),
          icon: Image.asset('assets/icons/sort.png', width: 24, height: 24),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox.square(
        dimension: 48,
        child: GlassIconButton(
          padding: EdgeInsets.zero,
          nativeSymbol: 'location',
          tooltip: t('map.buttons.reset'),
          onPressed: onLocate,
          icon: Image.asset('assets/icons/location.png', width: 24, height: 24),
        ),
      ),
    ],
  );
}

class MapLoadingNotice extends StatelessWidget {
  const MapLoadingNotice({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('map.loading.title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t('map.loading.subtitle'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MapRefreshErrorNotice extends StatelessWidget {
  const MapRefreshErrorNotice({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Material(
      color: const Color(0xFFFDF3D8),
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: Color(0xFF765B13),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t('map.offline.noData'),
                style: const TextStyle(
                  color: Color(0xFF5C470F),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              tooltip: t('map.offline.retry'),
              visualDensity: VisualDensity.compact,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Color(0xFF765B13)),
            ),
          ],
        ),
      ),
    ),
  );
}
