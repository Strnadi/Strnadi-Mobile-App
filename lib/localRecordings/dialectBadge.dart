import 'package:flutter/material.dart';
import 'package:strnadi/database/databaseNew.dart';

class DialectBadge extends StatelessWidget {

  final RecordingDialect dialect;

  const DialectBadge({
    Key? key,
    required this.dialect,
  }) : super(key: key);

  String _formatDuration(Duration d) {
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    final min = d.inMinutes.toString().padLeft(2, '0');
    return "$min:$sec,$ms";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dialekt',
            style: TextStyle(
              color: Colors.black,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.lightBlue.shade100,
                  border: Border.all(color: Colors.black),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dialect.dialect,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
