import 'package:flutter/gestures.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/registeration/nameReg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class RegMail extends StatefulWidget {
  const RegMail({super.key});

  @override
  State<RegMail> createState() => _RegMailState();
}

class _RegMailState extends State<RegMail> {
  bool _isChecked = false;
  final TextEditingController _emailController = TextEditingController();

  late bool _termsError = false;
  String? _emailErrorMessage;

  bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    // Whether all fields are valid
    final bool formValid = isValidEmail(_emailController.text) && _isChecked;

    return Scaffold(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                'Zadejte váš e-mail',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // "E-mail" label
              Text(
                'E-mail',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),

              // Email TextField
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  fillColor: Colors.grey[200],
                  filled: true,
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  errorText: _emailErrorMessage,
                ),
              ),
              const SizedBox(height: 16),

              // Smaller grey background for terms
              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Custom checkbox
                    CheckboxTheme(
                      data: CheckboxThemeData(
                        side: _isChecked
                            ? const BorderSide(width: 0, color: Colors.transparent)
                            : const BorderSide(width: 2, color: Colors.grey),
                      ),
                      child: Checkbox(
                        value: _isChecked,
                        onChanged: (bool? newValue) {
                          setState(() {
                            _isChecked = newValue ?? false;
                          });
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(2),
                        ),
                        fillColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.selected)) {
                            return Colors.black;
                          }
                          return Colors.white;
                        }),
                        checkColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(color: Colors.black),
                          children: [
                            TextSpan(
                              text:
                              'Zapojením do projektu občanské vědy Nářečí českých stranád ',
                            ),
                            TextSpan(
                              text: 'souhlasím s podmínkami',
                              style: TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_termsError)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'You must accept the terms to continue.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              // Larger "Pokračovat" button (full width)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    bool emailValid = isValidEmail(_emailController.text);
                    bool termsAccepted = _isChecked;

                    setState(() {
                      _emailErrorMessage = emailValid
                          ? null
                          : 'Please enter a valid email address';
                      _termsError = !termsAccepted;
                    });

                    if (emailValid && termsAccepted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RegName(
                            email: _emailController.text,
                            consent: true,
                          ),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    backgroundColor: formValid ? yellow : Colors.grey,
                    foregroundColor: formValid ? textColor : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: const Text('Pokračovat'),
                ),
              ),

              const SizedBox(height: 32),

              // Divider with "Nebo"
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Colors.grey.shade300,
                      thickness: 1,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Nebo'),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.grey.shade300,
                      thickness: 1,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // "Pokračovat přes Google" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Handle "Continue with Google" logic here
                  },
                  icon: Image.asset(
                    'assets/images/google.webp',
                    height: 24,
                    width: 24,
                  ),
                  label: const Text(
                    'Pokračovat přes Google',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 32),
        child: Row(
          children: List.generate(6, (index) {
            bool completed = index < 1;
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
    );
  }
}