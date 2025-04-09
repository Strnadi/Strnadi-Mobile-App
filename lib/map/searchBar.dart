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
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SearchBarWidget extends StatefulWidget {
  final void Function(LatLng) onLocationSelected;

  const SearchBarWidget({required this.onLocationSelected, super.key});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<_SearchResult> _results = [];

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.isEmpty) {
        setState(() => _results = []);
        return;
      }

      final url =
          'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5&countrycodes=cz';
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'FlutterMapApp/1.0 (marpecqueur@gmail.com)'
      });

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          _results = data
              .map((e) => _SearchResult(
            name: e['display_name'],
            latLng: LatLng(
              double.parse(e['lat']),
              double.parse(e['lon']),
            ),
          ))
              .toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search location...',
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
            ),
          ),
          if (_results.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
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
    );
  }
}

class _SearchResult {
  final String name;
  final LatLng latLng;

  _SearchResult({required this.name, required this.latLng});
}
