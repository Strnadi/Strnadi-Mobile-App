import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Register extends StatefulWidget {
  const Register({ super.key });

  @override
  State<Register> createState() => _RegisterState();

}

class _RegisterState extends State<Register> {

  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _NickController = TextEditingController();

  late bool _termsAgreement = false;

  void login(){

    final email = _emailController.text;
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in both fields');
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => HomePage()));
    }


  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }




  @override
  Widget build(BuildContext context) {

    return Center(
      child: Form(
        key: _GlobalKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Register',
              style: TextStyle(fontSize: 20),

            ),
            TextFormField(
              controller: _NickController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'username',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.name,

              // The validator receiv          es the text that the user has entered.
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter some text';
                }
                return null;
              },
            ),
            Text(
              'Name',
              style: TextStyle(fontSize: 20),

            ),
            TextFormField(
              controller: _NickController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.name,

              // The validator receiv          es the text that the user has entered.
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter some text';
                }
                return null;
              },
            ),

            Text(
              'Surename',
              style: TextStyle(fontSize: 20),

            ),
            TextFormField(
              controller: _NickController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Surename',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.name,

              // The validator receiv          es the text that the user has entered.
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter some text';
                }
                return null;
              },
            ),
            Text(
              'Email',
              style: TextStyle(fontSize: 20),

            ),
            TextFormField(
              controller: _emailController,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,

              // The validator receiv          es the text that the user has entered.
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter some text';
                }
                return null;
              },
            ),

            Text('Password',

              style: TextStyle(fontSize: 20),
            ),

            TextFormField(
              textAlign: TextAlign.center,
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'password',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.visiblePassword,
              // The validator receiv          es the text that the user has entered.
              validator:(value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter some text';
                }
                return null;
              },
            ),
            CheckboxListTile(
              title: const Text('I agree to the terms and conditions'),
              value: _termsAgreement,
              onChanged: (value) {
                setState(() {
                  _termsAgreement = value!;
                });
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton(
                onPressed: login,
                // Validate returns true if the form is valid, or false otherwise.
                child: const Text('Submit'),
              ),
            ),
          ],
        ),
      ),
    );

  }
}
