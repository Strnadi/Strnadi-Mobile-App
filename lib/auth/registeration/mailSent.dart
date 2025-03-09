import 'package:flutter/material.dart';
import 'package:strnadi/auth/login.dart';

class MailSent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            Text('Mail Sent'),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => Login()));
              },
              child: Text('Okay'),
            ),
          ],
        ),
      ),
    );
  }
}
