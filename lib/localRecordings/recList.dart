import 'package:flutter/material.dart';
import 'package:strnadi/bottomBar.dart';

class RecordItem {
  final String title;
  final String date;
  final String status;

  RecordItem({required this.title, required this.date, required this.status});
}

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sample data matching the screenshot
    final List<RecordItem> records = [
      RecordItem(
        title: 'Na chalupě',
        date: '29. 11. 2025',
        status: 'V databázi',
      ),
      RecordItem(
        title: 'Nevím',
        date: '29. 11. 2025',
        status: 'V databázi',
      ),
      RecordItem(
        title: 'Les na Dubině',
        date: '29. 11. 2025',
        status: 'Čeká na Wi-Fi připojení',
      ),
      RecordItem(
        title: 'Název záznamu 1',
        date: '29. 11. 2025',
        status: 'Čeká na Wi-Fi připojení',
      ),
    ];

    return ScaffoldWithBottomBar(
    appBarTitle: 'Záznamy',
      content: ListView.separated(
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
            onTap: () {},
          );
        },
      ),
    );
  }
}