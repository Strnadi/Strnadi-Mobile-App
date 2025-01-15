import 'package:flutter/material.dart';

enum AuthType { login, register }

class Authorizator extends StatefulWidget {
  final Widget login;
  final Widget register;

  const Authorizator({
    Key? key,
    required this.login,
    required this.register,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}

class _AuthState extends State<Authorizator> {
  AuthType authType = AuthType.login;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 20,
      children: [
        SegmentedButton<AuthType>(
          segments: const <ButtonSegment<AuthType>>[
            ButtonSegment<AuthType>(
                value: AuthType.login,
                label: Text('Login'),
                icon: Icon(Icons.key)),
            ButtonSegment<AuthType>(
                value: AuthType.register,
                label: Text('Register'),
                icon: Icon(Icons.account_circle_rounded)),
          ],
          selected: <AuthType>{authType},
          onSelectionChanged: (Set<AuthType> newSelection) {
            setState(() {
              authType = newSelection.first;
            });
          },
        ),
        Center(
          child: authType == AuthType.login ? widget.login : widget.register,
        )
      ],
    );
  }
}