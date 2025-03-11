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
import 'package:flutter/material.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/localRecordings/recListItem.dart';
import 'package:strnadi/localRecordings/recordingsDb.dart';

class RecordItem {
  final String title;
  final String date;
  final String status;

  RecordItem({required this.title, required this.date, required this.status});
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({Key? key}) : super(key: key);

  @override
  _RecordingScreenState createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {

  List<RecordItem> list = [];

  @override
  void initState() {
    super.initState();
    getRecordings();
  }

  void getRecordings() async {
    list = await LocalDb.GetRecordings();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var records = list.reversed.toList();
    return ScaffoldWithBottomBar(
      appBarTitle: 'Záznamy',
      content: Padding(
        padding: const EdgeInsets.all(10.0),
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: ListView.separated(
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(
                  records[index].title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Text(
                      records[index].date,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      records[index].status,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RecordingItem(recording: records[index]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
