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
import 'package:strnadi/localization/localization.dart';

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

  /// Determines if a prompt contains coordinates and extracts them
  /// Returns a LatLng object if valid coordinates are found, null otherwise
  LatLng? parseCoordinatesFromPrompt(String prompt) {
    if (prompt.isEmpty) return null;

    final normalized = prompt.trim();

    final directionalLatLon = RegExp(
      r'^([NS])?\s*(-?\d+(?:[.,]\d+)?)\s*([NS])?\s*[,;\s]+\s*([EW])?\s*(-?\d+(?:[.,]\d+)?)\s*([EW])?$',
      caseSensitive: false,
    );
    final directionalLonLat = RegExp(
      r'^([EW])?\s*(-?\d+(?:[.,]\d+)?)\s*([EW])?\s*[,;\s]+\s*([NS])?\s*(-?\d+(?:[.,]\d+)?)\s*([NS])?$',
      caseSensitive: false,
    );

    final latLonMatch = directionalLatLon.firstMatch(normalized);
    if (latLonMatch != null) {
      final lat = _parseCoordinateWithDirection(
        number: latLonMatch.group(2),
        prefixDirection: latLonMatch.group(1),
        suffixDirection: latLonMatch.group(3),
        positiveDirection: 'N',
        negativeDirection: 'S',
      );
      final lng = _parseCoordinateWithDirection(
        number: latLonMatch.group(5),
        prefixDirection: latLonMatch.group(4),
        suffixDirection: latLonMatch.group(6),
        positiveDirection: 'E',
        negativeDirection: 'W',
      );

      if (lat != null &&
          lng != null &&
          _isValidLatitude(lat) &&
          _isValidLongitude(lng)) {
        return LatLng(lat, lng);
      }
    }

    final lonLatMatch = directionalLonLat.firstMatch(normalized);
    if (lonLatMatch != null) {
      final lng = _parseCoordinateWithDirection(
        number: lonLatMatch.group(2),
        prefixDirection: lonLatMatch.group(1),
        suffixDirection: lonLatMatch.group(3),
        positiveDirection: 'E',
        negativeDirection: 'W',
      );
      final lat = _parseCoordinateWithDirection(
        number: lonLatMatch.group(5),
        prefixDirection: lonLatMatch.group(4),
        suffixDirection: lonLatMatch.group(6),
        positiveDirection: 'N',
        negativeDirection: 'S',
      );

      if (lat != null &&
          lng != null &&
          _isValidLatitude(lat) &&
          _isValidLongitude(lng)) {
        return LatLng(lat, lng);
      }
    }

    final decimalWithSeparator = RegExp(
      r'^(-?\d+(?:[.,]\d+)?)\s*[,;]\s*(-?\d+(?:[.,]\d+)?)$',
    );
    final decimalSeparatedBySpace = RegExp(
      r'^(-?\d+(?:[.,]\d+)?)\s+(-?\d+(?:[.,]\d+)?)$',
    );

    final decimalMatch = decimalWithSeparator.firstMatch(normalized) ??
        decimalSeparatedBySpace.firstMatch(normalized);
    if (decimalMatch != null) {
      final lat = _parseDecimalCoordinate(decimalMatch.group(1));
      final lng = _parseDecimalCoordinate(decimalMatch.group(2));
      if (lat != null &&
          lng != null &&
          _isValidLatitude(lat) &&
          _isValidLongitude(lng)) {
        return LatLng(lat, lng);
      }
    }

    return null;
  }

  double? _parseDecimalCoordinate(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  double? _parseCoordinateWithDirection({
    required String? number,
    required String? prefixDirection,
    required String? suffixDirection,
    required String positiveDirection,
    required String negativeDirection,
  }) {
    final base = _parseDecimalCoordinate(number);
    if (base == null) return null;

    final prefix = prefixDirection?.toUpperCase();
    final suffix = suffixDirection?.toUpperCase();
    if (prefix != null &&
        suffix != null &&
        prefix.isNotEmpty &&
        suffix.isNotEmpty &&
        prefix != suffix) {
      return null;
    }

    final direction = (prefix != null && prefix.isNotEmpty)
        ? prefix
        : ((suffix != null && suffix.isNotEmpty) ? suffix : null);
    if (direction == null) return base;
    if (direction == positiveDirection) return base.abs();
    if (direction == negativeDirection) return -base.abs();
    return null;
  }

  /// Helper: Validate latitude range (-90 to 90)
  bool _isValidLatitude(double lat) => lat >= -90 && lat <= 90;

  /// Helper: Validate longitude range (-180 to 180)
  bool _isValidLongitude(double lng) => lng >= -180 && lng <= 180;

  /// Simple check if a prompt looks like it might contain coordinates
  bool looksLikeCoordinates(String prompt) {
    return parseCoordinatesFromPrompt(prompt) != null;
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (query.isEmpty) {
        setState(() => _results = []);
        return;
      }

      if (looksLikeCoordinates(query)) {
        LatLng? coords = parseCoordinatesFromPrompt(query);
        if (coords != null) {
          setState(() {
            _results = [
              _SearchResult(
                  name: '${coords.latitude}, ${coords.longitude}',
                  latLng: coords)
            ];
          });
          return;
        }
      }

      final url =
          'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5&countrycodes=cz';
      final res = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'FlutterMapApp/1.0 (marpecqueur@gmail.com)'});

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
            decoration: InputDecoration(
              hintText: t('map.search.hint'),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: const OutlineInputBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(12))),
            ),
          ),
          if (_results.isNotEmpty)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(12)),
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
