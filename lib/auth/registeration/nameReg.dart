/*
 * Copyright (C) 2024 Marian Pecqueur
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/registeration/nameReg.dart';
import 'package:strnadi/auth/registeration/passwordReg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegName extends StatefulWidget {
  final email;
  final bool consent;

  const RegName({super.key, required this.email, required this.consent});

  @override
  State<RegName> createState() => _RegNameState();
}

class _RegNameState extends State<RegName> {
  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _nickController = TextEditingController();

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

    final halfScreen = MediaQuery.of(context).size.height * 0.2;

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Form(
          key: _GlobalKey,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: halfScreen),
                  child: Column(
                    children: [
                      const Text(
                        'Jak se jmenujete?',
                        style: TextStyle(fontSize: 40, color: Colors.black, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          label: RichText(
                            text: TextSpan(
                              text: 'Jmeno',
                              children: const <TextSpan>[
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _surnameController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          label: RichText(
                            text: TextSpan(
                              text: 'Prijmeni',
                              children: const <TextSpan>[
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nickController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          label: RichText(
                            text: TextSpan(
                              text: 'Nick',
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all<Color>(
                          Colors.black,
                        ),
                        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                      ),
                      onPressed: () {
                        // Validate the form fields
                        if (_GlobalKey.currentState?.validate() ?? false) {
                          // If valid, proceed to the next screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RegPassword(
                                email: widget.email,
                                consent: widget.consent,
                                name: _nameController.text,
                                surname: _surnameController.text,
                                nickname: _nickController.text,
                              ),
                            ),
                          );
                        } else {
                          // Optionally, show an error message if validation fails
                          _showMessage(
                              'Please fix the errors before proceeding.');
                        }
                      },
                      child: const Text('Submit', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
