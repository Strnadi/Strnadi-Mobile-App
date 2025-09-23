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
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../database/databaseNew.dart';


class UserBadge extends StatefulWidget {
  final UserData user;

  const UserBadge({Key? key, required this.user}) : super(key: key);

  @override
  _UserBadgeState createState() => _UserBadgeState();
}

class _UserBadgeState extends State<UserBadge> {
  late Uint8List profileImageBytes;

  @override
  void initState() {
    super.initState();
    if (widget.user.ProfilePic != null){

      profileImageBytes = base64Decode(widget.user.ProfilePic!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.user.ProfilePic != null ) CircleAvatar(
          radius: 20,
          backgroundImage: MemoryImage(profileImageBytes),
        ) else CircleAvatar(radius: 20, backgroundImage: AssetImage("./assets/images/default.jpg"),),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.user.NickName ?? '${widget.user.FirstName} ${widget.user.LastName}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              widget.user.NickName != null ? "${widget.user.FirstName} ${widget.user.LastName}" : "Uzivatel nema prezdivku",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}