import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';

class NotificationScreen extends StatefulWidget {
  @override
  _NotificationScreenState createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> notifications = [];

  void getNotifications() async {
    setState(() async {
      notifications = await DatabaseNew.getNotificationList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Oznámení',
      content: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return ListTile(
            title: Text(
              notification.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(notification.message),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(notification.time, style: TextStyle(color: Colors.grey)),
                if (notification.unread)
                  const Icon(Icons.circle, color: Colors.black, size: 10),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationItem {
  final String title;
  final String message;
  final String time;
  final bool unread;

  NotificationItem({
    required this.title,
    required this.message,
    required this.time,
    required this.unread,
  });
}