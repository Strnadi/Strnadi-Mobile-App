/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
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
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:strnadi/api/controllers/map_search_controller.dart';
import 'package:strnadi/api/models/map_search_result.dart';
import 'coordinate_parser.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/localization/localization.dart';

class SearchBarWidget extends StatefulWidget {
  final void Function(LatLng) onLocationSelected;

  const SearchBarWidget({
    required this.onLocationSelected,
    this.searchController = const MapSearchController(),
    super.key,
  });

  final MapSearchController searchController;

  @override
  State<SearchBarWidget> createState() => SearchBarWidgetState();
}

class SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  int _searchGeneration = 0;
  List<MapSearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted && !_focusNode.hasFocus) {
        setState(() => _results = []);
      }
    });
  }

  void closeSearch() {
    setState(() => _results = []);
    _focusNode.unfocus();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final int generation = ++_searchGeneration;
    if (_results.isNotEmpty) {
      setState(() => _results = []);
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      if (query.isEmpty) {
        setState(() => _results = []);
        return;
      }

      if (looksLikeCoordinates(query)) {
        LatLng? coords = parseCoordinatesFromPrompt(query);
        if (coords != null) {
          if (!mounted || generation != _searchGeneration) {
            return;
          }
          setState(() {
            _results = [
              MapSearchResult(
                name: '${coords.latitude}, ${coords.longitude}',
                latLng: coords,
              ),
            ];
          });
          return;
        }
      }

      try {
        final parsed = await widget.searchController.search(query);
        if (!mounted || generation != _searchGeneration) {
          return;
        }
        setState(() {
          _results = parsed;
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) {
          return;
        }
        setState(() => _results = []);
      }
    });
  }

  @override
  void dispose() {
    _searchGeneration++;
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      onTapOutside: (_) => closeSearch(),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: t('map.search.hint'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
              ),
            ),
            if (_results.isNotEmpty)
              Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    return ListTile(
                      title: Text(result.name),
                      onTap: () {
                        widget.onLocationSelected(result.latLng);
                        _controller.clear();
                        setState(() => _results = []);
                        FocusScope.of(context).unfocus();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
