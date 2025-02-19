import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/HealthCheck/serverHealth.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class UserPage extends StatefulWidget {
  const UserPage({Key? key}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {

  @override
  void initState() {
    super.initState();
    getUsername();
  }

  late String userName = 'username';
  late String lastName = 'lastname';

  final logger = Logger();

  // todo finish the getUsername function

  void getUsername() async {
    final secureStorage = const FlutterSecureStorage();

    final username = await secureStorage.containsKey(key: 'user');
    if (username) {
      var username = await secureStorage.read(key: 'user');
      var lastname = await secureStorage.read(key: 'lastname');
      setState(() {
        userName = username!;
        lastName = lastname!;
      });
      logger.i("user name was cached");
      return;
    }

    final jwt = await secureStorage.read(key: 'token');

    final Uri url = Uri.parse('https://strnadiapi.slavetraders.tech/users').replace(queryParameters: {
      'jwt': jwt,
    });

    print("url: $url");

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          userName = data['firstName'];
          lastName = data['lastName'];
        });
        secureStorage.write(key: 'user', value: data['firstName']);
        secureStorage.write(key: "lastname", value: data['lastName']);
      } else {
      }
    } catch (error) {
      Sentry.captureException(error);
    }

  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'User Page',
      logout: true,
      content: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              height: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: const AssetImage('./assets/images/default.jpg'),
                  ),
                  Text(userName + " " + lastName, style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),)
                ],
              ),
            ),
            ServerHealth(),
            ElevatedButton(
              onPressed: () {
                logout(context);
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      ),
    );
  }


  void logout(BuildContext context) {
    final localStorage = const FlutterSecureStorage();
    localStorage.delete(key: 'token');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MyApp()),
          (route) => false, // Remove all previous routes
    );
  }
}
