import 'dart:convert';
import 'dart:typed_data';

const String profileFirstNameStorageKey = 'firstName';
const String profileLastNameStorageKey = 'lastName';
const String profileNicknameStorageKey = 'nick';
const String profileRoleStorageKey = 'role';
const int maxProfilePhotoBytes = 8 * 1024 * 1024;

class ProfileAccountException implements Exception {
  const ProfileAccountException(this.message);

  final String message;

  @override
  String toString() => 'ProfileAccountException: $message';
}

class UserProfileData {
  const UserProfileData({
    required this.nickname,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.postCode,
    required this.city,
    required this.role,
  });

  final String nickname;
  final String email;
  final String firstName;
  final String lastName;
  final int? postCode;
  final String? city;
  final String? role;
}

Map<String, dynamic>? decodeProfileMapPayload(Object? payload) {
  try {
    if (payload is Map) {
      return payload.cast<String, dynamic>();
    }
    if (payload is String) {
      final Object? decoded = jsonDecode(payload);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    }
    if (payload is List<int>) {
      final Object? decoded = jsonDecode(utf8.decode(payload));
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    }
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
  return null;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) return null;
  final String normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _profileString(Object? value) {
  if (value == null) return '';
  return value is String ? value : '';
}

int? _profilePostCode(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

UserProfileData? parseSuccessfulUserProfile({
  required int? statusCode,
  required Object? payload,
}) {
  if (statusCode != 200) return null;
  final Map<String, dynamic>? data = decodeProfileMapPayload(payload);
  if (data == null) return null;

  final Object? rawEmail = data['email'];
  if (rawEmail is! String || rawEmail.trim().isEmpty) return null;

  final Object? rawPostCode = data['postCode'];
  final int? postCode = _profilePostCode(rawPostCode);
  if (rawPostCode != null && postCode == null) return null;

  final Object? rawCity = data['city'];
  if (rawCity != null && rawCity is! String) return null;

  final Object? rawRole = data['role'];
  if (rawRole != null && rawRole is! String) return null;

  return UserProfileData(
    nickname: _profileString(data['nickname']),
    email: rawEmail.trim(),
    firstName: _profileString(data['firstName']),
    lastName: _profileString(data['lastName']),
    postCode: postCode,
    city: _optionalString(rawCity),
    role: _optionalString(rawRole),
  );
}

Map<String, dynamic>? buildUserProfilePatch({
  required String nickname,
  required String firstName,
  required String lastName,
  required String postCode,
  required String city,
}) {
  final String normalizedPostCode = postCode.trim();
  final int? parsedPostCode =
      normalizedPostCode.isEmpty ? null : int.tryParse(normalizedPostCode);
  if (normalizedPostCode.isNotEmpty && parsedPostCode == null) return null;

  String? optional(String value) {
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  return <String, dynamic>{
    'nickname': optional(nickname),
    'firstName': optional(firstName),
    'lastName': optional(lastName),
    'postCode': parsedPostCode,
    'city': optional(city),
  };
}

String profilePhotoCacheKey({
  required String ownerUserId,
  required String environment,
}) {
  final int? numericOwner = int.tryParse(ownerUserId.trim());
  final String normalizedEnvironment = environment.trim().toLowerCase();
  if (numericOwner == null ||
      numericOwner <= 0 ||
      normalizedEnvironment.isEmpty) {
    throw const ProfileAccountException(
      'A profile cache key requires an owner and environment.',
    );
  }
  return 'profile-photo-v2-'
      '${Uri.encodeComponent(normalizedEnvironment)}-$numericOwner';
}

String profilePhotoFormatFromPath(String filePath) {
  final int separator = filePath.lastIndexOf('.');
  if (separator < 0 || separator == filePath.length - 1) return 'jpg';
  final String extension = filePath.substring(separator + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension) ? extension : 'jpg';
}

enum ProfilePhotoPublishOutcome {
  published,
  uploadRejected,
  sessionChanged,
  cacheWriteFailed,
}

/// Publishes a selected profile photo in a fail-closed order.
///
/// The visible path and account-scoped cache are never touched before the
/// backend accepts the candidate. A session switch after the request also
/// prevents the old account's result from becoming visible in the new one.
class ProfilePhotoPublishCoordinator {
  const ProfilePhotoPublishCoordinator();

  Future<ProfilePhotoPublishOutcome> publishBoundedCandidate({
    required Future<int> Function() candidateLength,
    required Future<Uint8List> Function() readCandidate,
    required Future<int?> Function(Uint8List bytes) uploadCandidate,
    required Future<bool> Function() isSessionCurrent,
    required Future<String> Function(Uint8List bytes) commitScopedCache,
    required Future<void> Function(String cachedPath) publishVisiblePath,
    int maximumBytes = maxProfilePhotoBytes,
  }) async {
    if (maximumBytes <= 0) {
      throw const ProfileAccountException(
        'The profile photo byte limit must be positive.',
      );
    }
    final int declaredLength = await candidateLength();
    if (declaredLength <= 0 || declaredLength > maximumBytes) {
      throw const ProfileAccountException(
        'The selected profile photo has an invalid byte length.',
      );
    }

    final Uint8List bytes = await readCandidate();
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const ProfileAccountException(
        'The selected profile photo exceeds the byte limit.',
      );
    }

    return publish(
      uploadCandidate: () => uploadCandidate(bytes),
      isSessionCurrent: isSessionCurrent,
      commitScopedCache: () => commitScopedCache(bytes),
      publishVisiblePath: publishVisiblePath,
    );
  }

  Future<ProfilePhotoPublishOutcome> publish({
    required Future<int?> Function() uploadCandidate,
    required Future<bool> Function() isSessionCurrent,
    required Future<String> Function() commitScopedCache,
    required Future<void> Function(String cachedPath) publishVisiblePath,
  }) async {
    final int? statusCode = await uploadCandidate();
    if (statusCode != 200) {
      return ProfilePhotoPublishOutcome.uploadRejected;
    }
    if (!await isSessionCurrent()) {
      return ProfilePhotoPublishOutcome.sessionChanged;
    }

    late final String cachedPath;
    try {
      cachedPath = await commitScopedCache();
    } catch (_) {
      return ProfilePhotoPublishOutcome.cacheWriteFailed;
    }

    if (!await isSessionCurrent()) {
      return ProfilePhotoPublishOutcome.sessionChanged;
    }
    await publishVisiblePath(cachedPath);
    return ProfilePhotoPublishOutcome.published;
  }
}
