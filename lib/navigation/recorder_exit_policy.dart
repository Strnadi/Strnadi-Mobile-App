/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
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

/// Resolves any in-progress recording before a route can remove its owner.
///
/// The recorder supplies the implementation so navigation code never needs to
/// know about recorder state, files, or cleanup details. Returning `false`
/// keeps the current route in place.
typedef RecorderExitPolicy = Future<bool> Function();

Future<bool> permitsRecorderExit(RecorderExitPolicy? policy) async {
  return policy == null || await policy();
}
