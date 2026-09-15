import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/services/map_api_service.dart';

export 'package:strnadi/api/services/map_api_service.dart'
    show ClusterSnapshotExpired;

class MapClusterPicker extends StatefulWidget {
  const MapClusterPicker({
    super.key,
    required this.cluster,
    required this.loadPage,
    required this.isCurrent,
    required this.onExpired,
    required this.onSelect,
  });
  final MapCluster cluster;
  final Future<MapClusterItemsPage> Function(String cursor) loadPage;
  final bool Function() isCurrent;
  final VoidCallback onExpired;
  final ValueChanged<int> onSelect;
  @override
  State<MapClusterPicker> createState() => _MapClusterPickerState();
}

class _MapClusterPickerState extends State<MapClusterPicker> {
  late final List<MapClusterItem> _items = [...widget.cluster.items];
  late String? _cursor = widget.cluster.nextItemsCursor;
  bool _loading = false, _failed = false;
  Future<void> _more() async {
    if (_loading || _cursor == null) return;
    if (!widget.isCurrent()) {
      widget.onExpired();
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.loadPage(_cursor!);
      if (!mounted) return;
      if (!widget.isCurrent()) {
        widget.onExpired();
        return;
      }
      final ids = _items.map((i) => i.recordingId).toSet();
      final total = _items.length + page.items.length;
      if (page.clusterId != widget.cluster.id ||
          page.count != widget.cluster.count ||
          page.items.any((i) => ids.contains(i.recordingId)) ||
          page.items.first.recordingId <= _items.last.recordingId ||
          total > page.count ||
          page.hasMoreItems != (total < page.count) ||
          (page.hasMoreItems && page.nextItemsCursor == _cursor)) {
        throw const FormatException('Inconsistent cluster continuation.');
      }
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextItemsCursor;
      });
    } on ClusterSnapshotExpired {
      if (mounted) widget.onExpired();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${t('map.clusterPicker.title')} (${widget.cluster.count})',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return ListTile(
                  key: ValueKey(item.recordingId),
                  title: Text(
                    item.name?.trim().isNotEmpty == true
                        ? item.name!
                        : '${t('map.clusterPicker.recording')} ${item.recordingId}',
                  ),
                  subtitle: Text(
                    '${_sourceLabel(item.source)} • '
                    '${MaterialLocalizations.of(context).formatShortDate(item.createdAt.toLocal())}',
                  ),
                  onTap: () {
                    if (widget.isCurrent()) {
                      widget.onSelect(item.recordingId);
                    } else {
                      widget.onExpired();
                    }
                  },
                );
              },
            ),
          ),
          if (_failed) Text(t('map.clusterPicker.failed')),
          if (_cursor != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _loading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _more,
                      child: Text(
                        t(
                          _failed
                              ? 'map.clusterPicker.retry'
                              : 'map.clusterPicker.more',
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ),
  );
}

String _sourceLabel(String source) => t(switch (source) {
  'confirmed' => 'map.clusterPicker.sources.confirmed',
  'ai' => 'map.clusterPicker.sources.ai',
  'user' => 'map.clusterPicker.sources.user',
  _ => 'map.clusterPicker.sources.unknown',
});
