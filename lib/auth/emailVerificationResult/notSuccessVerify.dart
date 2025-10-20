import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';

/// A screen shown when e‑mail verification fails.
class EmailVerificationFailed extends StatelessWidget {
  const EmailVerificationFailed({Key? key}) : super(key: key);

  /// Navigates back to the login / authorizator flow.
  void _goToLogin(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/authorizator',
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('signup.emailVerify.failed.title')),
        backgroundColor: const Color(0xFFFFD641), // same brand yellow
        foregroundColor: const Color(0xFF2D2B18), // same brand dark
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 100,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            Text(
              t('signup.emailVerify.failed.message'),
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF2D2B18),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              t('signup.emailVerify.failed.subtitle'),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2D2B18),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _goToLogin(context),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFFFFD641),
                  foregroundColor: const Color(0xFF2D2B18),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                child: Text(t('signup.emailVerify.buttons.tryAgain')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}