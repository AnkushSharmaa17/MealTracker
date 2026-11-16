import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Checks GitHub for a newer release of this app.
///
/// The repository is public, so no authentication is required — we only
/// read the latest published release and its APK asset.
class UpdateService {
  /// GitHub user / org name.
  static const String _owner = 'AnkushSharmaa17';

  /// GitHub repository name.
  static const String _repo = 'MealTracker';

  /// Returns update info if a newer version exists, otherwise null.
  ///
  /// The returned map has these keys:
  ///   - latestVersion : e.g. "1.1.1"
  ///   - releaseNotes  : free-form text from the release body
  ///   - downloadUrl   : direct APK URL
  static Future<Map<String, String>?> checkForUpdate() async {
    try {
      // 1. Current installed version (e.g. "1.1.0").
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 2. Fetch latest release from GitHub public API.
      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'MealTracker-App',
        },
      ).timeout(const Duration(seconds: 10));

      // No releases yet, or something went wrong.
      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // 3. Parse version + download URL.
      final rawTag = (data['tag_name'] as String?) ?? '';
      final latestVersion =
          rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;

      if (latestVersion.isEmpty) return null;

      final releaseNotes =
          (data['body'] as String?)?.trim() ?? 'Bug fixes and improvements.';

      // 4. Find the APK asset.
      final assets = (data['assets'] as List?) ?? const [];
      String? downloadUrl;
      for (final asset in assets) {
        final name = (asset['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          downloadUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      if (downloadUrl == null) return null;

      // 5. Compare versions.
      if (_isNewer(currentVersion, latestVersion)) {
        return {
          'latestVersion': latestVersion,
          'releaseNotes': releaseNotes,
          'downloadUrl': downloadUrl,
        };
      }

      return null;
    } catch (_) {
      // Network issues, JSON errors, etc. Fail silently — the app must never
      // crash just because the update check failed.
      return null;
    }
  }

  /// Returns true when [latest] is strictly newer than [current].
  /// Both strings are of the form "x.y.z" (or "x.y.z+build").
  static bool _isNewer(String current, String latest) {
    try {
      final cur = _parse(current);
      final lat = _parse(latest);
      for (var i = 0; i < 3; i++) {
        if (lat[i] > cur[i]) return true;
        if (lat[i] < cur[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parse(String version) {
    // Strip any "+build" suffix, then split by dots.
    final core = version.split('+').first;
    final parts = core.split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
    ];
  }
}
