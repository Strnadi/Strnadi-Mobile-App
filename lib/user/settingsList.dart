import 'package:flutter/material.dart';

class MenuScreen extends StatelessWidget {
  final List<String> menuItems = [
    'Osobní údaje',
    'Nastavení',
    'Vaše úspěchy',
    'Příručka',
    'O projektu',
    'O aplikaci',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        height: 500,
        width: double.infinity,
        child: ListView.separated(
          itemCount: menuItems.length,
          separatorBuilder: (context, index) => Divider(),
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(menuItems[index]),
              trailing: Icon(Icons.arrow_forward_ios),
              onTap: () {
                // Handle navigation
              },
            );
          },
        ),
      ),
    );
  }
}