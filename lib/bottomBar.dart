import 'package:flutter/material.dart';
import 'package:strnadi/home.dart';
import 'package:strnadi/map/map.dart';
import 'package:strnadi/recording/recorder.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';

class ScaffoldWithBottomBar extends StatelessWidget {
  final String appBarTitle;
  final Widget content;

  const ScaffoldWithBottomBar({
    Key? key,
    required this.appBarTitle,
    required this.content,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: content,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (appBarTitle == 'Recording Screen') {
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RecorderWithSpectogram()),
          );
        },
        child: const Icon(
          Icons.mic,
          size: 30,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: const ReusableBottomAppBar(),
    );
  }
}

class ReusableBottomAppBar extends StatelessWidget {
  const ReusableBottomAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.home),
            iconSize: 30.0,
            onPressed: () {
              // Avoid navigating to HomePage if already there
              if (ModalRoute.of(context)?.settings.name != '/home') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HomePage(),
                    settings: const RouteSettings(name: '/home'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.map),
            iconSize: 30.0,
            onPressed: () {

              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OSMmap(),
                    settings: const RouteSettings(name: '/map'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
