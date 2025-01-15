import 'package:geolocator/geolocator.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/register.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> requestLocationPermission() async {
    LocationPermission permission;

    // Check if location services are enabled
    if (!await Geolocator.isLocationServiceEnabled()) {
      print('Location services are disabled.');
      return false;
    }

    // Check the current permission status
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission if denied
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permission denied.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied.');
      return false;
    }

    // Permission granted
    return true;
  }

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

