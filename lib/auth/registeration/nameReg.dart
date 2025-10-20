/*
 * Copyright (C) 2025 Marian Pecqueur & Jan Drobílek
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
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/auth/registeration/passwordReg.dart';

import 'cityReg.dart';
import 'package:flutter/material.dart';

Logger logger = Logger();

class RegName extends StatefulWidget {
  final String email;
  final String jwt;
  final String? name;
  final String? surname;
  final String? password;
  final String? appleId;
  final bool consent;

  const RegName({super.key, required this.email, required this.consent, required this.jwt, this.password, this.name, this.surname, this.appleId});

  @override
  State<RegName> createState() => _RegNameState();
}

class _RegNameState extends State<RegName> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _nickController = TextEditingController();

  /// Form is valid if both required fields (Jméno, Příjmení) are non-empty.
  bool get _isFormValid =>
      _nameController.text.trim().isNotEmpty &&
          _surnameController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Colors and styling constants
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    if(widget.name!=null){
      _nameController.text = widget.name!;
    }
    if(widget.surname!=null){
      _surnameController.text = widget.surname!;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if(didPop) return;
        try {
          GoogleSignInService.signOut();
        }
        catch(e){
          logger.w('Google sign out failed: $e');
        }
        Navigator.pop(context);
        return;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: Image.asset(
              'assets/icons/backButton.png',
              width: 30,
              height: 30,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(t('signup.name.title'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // "Jméno *" label and text field
                  Text(t('signup.name.name'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    keyboardType: TextInputType.name,
                    decoration: InputDecoration(
                      fillColor: Colors.grey[200],
                      filled: true,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return t('signup.name.errors.null_name_err');
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // "Příjmení *" label and text field
                  Text(t('signup.name.last_name'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _surnameController,
                    keyboardType: TextInputType.name,
                    decoration: InputDecoration(
                      fillColor: Colors.grey[200],
                      filled: true,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return t('signup.name.errors.null_surname_err');
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // "Přezdívka" label and text field (optional)
                  Text(t('signup.name.nickname'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nickController,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      hintText: t('signup.name.nickname_hint'),
                      fillColor: Colors.grey[200],
                      filled: true,
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(t('signup.name.real_name_warning'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // "Pokračovat" button: yellow if valid, otherwise grey.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // Trigger validation; error messages and red outlines will display if fields are invalid.
                        if (_formKey.currentState?.validate() ?? false) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RegLocation(
                                email: widget.email,
                                consent: widget.consent,
                                name: _nameController.text.trim(),
                                surname: _surnameController.text.trim(),
                                nickname: _nickController.text.trim(),
                                password: widget.password,
                                appleId: widget.appleId,
                                jwt: widget.jwt,
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: _isFormValid ? yellow : Colors.grey,
                        foregroundColor: _isFormValid ? textColor : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: Text(t('signup.mail.buttons.continue')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom segmented progress bar with larger bottom padding
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 48),
          child: Row(
            children: List.generate(5, (index) {
              bool completed = index < 3;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: completed ? yellow : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}