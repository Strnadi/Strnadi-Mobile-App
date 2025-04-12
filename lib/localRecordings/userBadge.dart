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
              widget.user.NickName ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              "${widget.user.FirstName} ${widget.user.LastName}",
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