/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/widgets/progressIndicator.dart';

import '../../config/config.dart';
import '../../localization/localization.dart';

class Achievement {
  final String title;
  final String description;
  final String imageUrl;
  final bool unlocked;

  Achievement({
    required this.title,
    required this.description,
    required this.imageUrl,
    this.unlocked = true,
  });
}

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  late Future<List<Achievement>> _achievementsFuture;
  List<Achievement> achievements = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadAllAchievements();
  }

  Future<void> loadAllAchievements() async {
    final userAchs = await getUserAchievement();
    final allAchs = await getAllAchievements();

    setState(() {
      achievements = mergeAchievements(userAchs, allAchs);
      isLoading = false;
    });
  }

  List<Achievement> mergeAchievements(
    List<Achievement> userAchievements,
    List<Achievement> allAchievements,
  ) {
    final userAchievementMap = {
      for (var achievement in userAchievements) achievement.title: achievement
    };

    return allAchievements.map((achievement) {
      if (userAchievementMap.containsKey(achievement.title)) {
        return userAchievementMap[achievement.title]!;
      }
      return achievement;
    }).toList();
  }

  Future<List<Achievement>> getUserAchievement() async {
    List<Achievement> list = [];

    var storage = FlutterSecureStorage();

    var token = await storage.read(key: 'userId');

    logger.i('$token');

    final url = Uri.parse("https://${Config.host}/achievements?userId=$token");
    try {
      final value = await http.get(
        url,
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/json',
        },
      );
      if (value.statusCode == 200) {
        logger.i('achievements ${value.body}');
        // Parse your achievements here and add to list
        // Example:
        list = await parseAchievements(value.body, defaultVal: true);
      } else {
        logger.e('Failed to fetch achievements: ${value.statusCode}');
      }
    } catch (e, st) {
      logger.e('Profile picture upload error', error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }

    setState(() {
      isLoading = false;
      achievements = list;
    });

    return list;
  }

  Future<List<Achievement>> parseAchievements(String jsonString,
      {bool defaultVal = false}) async {
    var language = (await Config.getLanguagePreference()).toString();

    logger.i(language);

    try {
      final parsed = json.decode(jsonString);

      logger.i(parsed);

      // Handle if response is a list directly
      if (parsed is List) {
        return parsed
            .map<Achievement>((json) => Achievement(
                  title: _getLocalizedContent(
                          json['contents'], language, 'title') ??
                      'Unknown',
                  description: _getLocalizedContent(
                          json['contents'], language, 'description') ??
                      '',
                  imageUrl:
                      json['imageUrl'] ?? 'https://via.placeholder.com/150',
                  unlocked: json['unlocked'] ?? defaultVal,
                ))
            .toList();
      }

      // Handle if response is an object with data property
      if (parsed is Map && parsed.containsKey('data')) {
        final data = parsed['data'];
        if (data is List) {
          return data
              .map<Achievement>((json) => Achievement(
                    title: json['title'] ?? 'Unknown',
                    description: json['description'] ?? '',
                    imageUrl:
                        json['imageUrl'] ?? 'https://via.placeholder.com/150',
                    unlocked: json['unlocked'] ?? true,
                  ))
              .toList();
        }
      }

      return [];
    } catch (e, st) {
      logger.e('Error parsing achievements', error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
      return [];
    }
  }

  /// Gets localized content from an array of language objects
  ///
  /// Searches for an object with a matching languageCode and returns the requested field.
  /// Falls back to the first item if the language is not found.
  ///
  /// Example structure:
  /// [
  ///   {"languageCode": "cs", "title": "Prvni Nahravka", "description": "Nahrajte prvni nahravku"},
  ///   {"languageCode": "en", "title": "First Recording", "description": "Record your first recording"}
  /// ]
  String? _getLocalizedContent(
    dynamic contentArray,
    String languageCode,
    String fieldName,
  ) {
    if (contentArray == null || contentArray is! List || contentArray.isEmpty) {
      return null;
    }

    try {
      // Try to find content with matching languageCode
      for (var item in contentArray) {
        if (item is Map &&
            item['languageCode']?.toString() == languageCode &&
            item[fieldName] != null) {
          return item[fieldName].toString();
        }
      }

      // Fallback: return the field from the first item
      final firstItem = contentArray.first;
      if (firstItem is Map && firstItem[fieldName] != null) {
        return firstItem[fieldName].toString();
      }

      return null;
    } catch (e) {
      logger.w('Error getting localized content for field: $fieldName',
          error: e);
      return null;
    }
  }

  Future<List<Achievement>> getAllAchievements() async {
    List<Achievement> list = [];

    final url = Uri.parse("https://${Config.host}/achievements");
    try {
      final value = await http.get(
        url,
        headers: {
          'Accept': '*/*',
          'Content-Type': 'application/json',
        },
      );
      if (value.statusCode == 200) {
        logger.i('achievements ${value.body}');
        // Parse your achievements here and add to list
        // Example:
        list = await parseAchievements(value.body);
      } else {
        logger.e('Failed to fetch achievements: ${value.statusCode}');
      }
    } catch (e, st) {
      logger.e('Profile picture upload error', error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }

    setState(() {
      achievements = list;
      isLoading = false;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    double progress = achievements.where((a) => a.unlocked).length.toDouble() /
        achievements.length.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Achievements'),
        centerTitle: true,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${achievements.where((a) => a.unlocked).length}/${achievements.length} Unlocked',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CustomProgressIndicator(
                            value: progress,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return AchievementCard(
                            achievement: achievements[index]);
                      },
                      childCount: achievements.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class AchievementCard extends StatelessWidget {
  final Achievement achievement;

  const AchievementCard({
    Key? key,
    required this.achievement,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: achievement.unlocked ? 2 : 0,
      child: InkWell(
        onTap: () {
          showAchievementDialog(context);
        },
        child: Opacity(
          opacity: achievement.unlocked ? 1.0 : 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: achievement.unlocked
                        ? Colors.grey[200]
                        : Colors.grey[350],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.network(
                        achievement.imageUrl,
                        fit: BoxFit.cover,
                        color: achievement.unlocked
                            ? null
                            : Colors.black.withValues(alpha: 0.3),
                        colorBlendMode: achievement.unlocked
                            ? BlendMode.multiply
                            : BlendMode.darken,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.emoji_events,
                            size: 48,
                            color: achievement.unlocked
                                ? Colors.amber
                                : Colors.grey[400],
                          );
                        },
                      ),
                      if (!achievement.unlocked)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      achievement.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color:
                                achievement.unlocked ? null : Colors.grey[600],
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      achievement.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: achievement.unlocked
                                ? Colors.grey[600]
                                : Colors.grey[500],
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showAchievementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(achievement.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Opacity(
                opacity: achievement.unlocked ? 1.0 : 0.6,
                child: Image.network(
                  achievement.imageUrl,
                  height: 150,
                  width: 150,
                  fit: BoxFit.cover,
                  color: achievement.unlocked
                      ? null
                      : Colors.black.withValues(alpha: 0.3),
                  colorBlendMode: achievement.unlocked
                      ? BlendMode.multiply
                      : BlendMode.darken,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 150,
                      width: 150,
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.emoji_events,
                        size: 64,
                        color:
                            achievement.unlocked ? Colors.amber : Colors.grey,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              achievement.description,
              style: TextStyle(
                color: achievement.unlocked ? null : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: achievement.unlocked
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                border: Border.all(
                  color: achievement.unlocked
                      ? Colors.green.shade300
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                achievement.unlocked ? '✓ Unlocked' : '🔒 Locked',
                style: TextStyle(
                  color: achievement.unlocked
                      ? Colors.green.shade700
                      : Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
