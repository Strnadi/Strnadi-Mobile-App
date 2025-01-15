import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Login extends StatefulWidget {
  const Login({ super.key });

  @override
  State<Login> createState() => _LoginState();

}

class _LoginState extends State<Login> {

  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
        title: const Text('Login'),
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

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            Form(
              key: _GlobalKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    'Login',
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
          ],
        ),
      ],
    );

  }
}
