import 'package:flutter/material.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/localization/localization.dart';

class MapLegendSheet extends StatelessWidget {
  const MapLegendSheet({super.key, required this.dialectCodes});

  final List<String> dialectCodes;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewPaddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          Text(
            t('map.legend.title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 16),
          Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final code in dialectCodes) _DialectLegendItem(code: code),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _MarkerStatusLegendItem(
                  showCenterDot: true,
                  label: t('map.legend.status.aiAssisted'),
                ),
                _MarkerStatusLegendItem(
                  showCenterDot: false,
                  label: t('map.legend.status.adminConfirmed'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  backgroundColor: const Color(0xFFFFD641),
                  foregroundColor: const Color(0xFF2D2B18),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(t('map.dialogs.error.close')),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DialectLegendItem extends StatelessWidget {
  const _DialectLegendItem({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DynamicIcon(
          icon: Icons.circle,
          iconSize: 18,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          dialects: [code],
        ),
        const SizedBox(width: 6),
        Text(
          code == 'Unknown'
              ? t('dialectKeywords.unassessed')
              : DialectKeywordTranslator.toLocalized(code),
        ),
      ],
    ),
  );
}

class _MarkerStatusLegendItem extends StatelessWidget {
  const _MarkerStatusLegendItem({
    required this.showCenterDot,
    required this.label,
  });

  final bool showCenterDot;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DynamicIcon(
          icon: Icons.circle,
          iconSize: 18,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          border: Border.all(color: Colors.black54),
          showCenterDot: showCenterDot,
          dotColor: Colors.black,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}
