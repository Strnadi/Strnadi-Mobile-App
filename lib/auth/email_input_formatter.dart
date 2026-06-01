import 'package:flutter/services.dart';

class LowerCaseEmailInputFormatter extends TextInputFormatter {
  const LowerCaseEmailInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lowerCaseText = newValue.text.toLowerCase();
    if (lowerCaseText == newValue.text) return newValue;

    return newValue.copyWith(
      text: lowerCaseText,
      composing: TextRange.empty,
    );
  }
}
