import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/register.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Welcome to Flutter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          shape: ContinuousRectangleBorder(),
        ),
        body: Column(
          children: [
            Authorizator(login: Login(), register: Register()),
          ],
        )
      ),
    );
  }
}

