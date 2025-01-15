import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strnadi/bottomBar.dart';


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Welcome to Flutter',
      content: const Center(
        child: Text(
          'This is the main page content!',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
