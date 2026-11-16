import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';

/// Premium dialog shown when a newer app version is available.
///
/// Matches the tomato-red theme, shows release notes and lets the user
/// download the latest APK from GitHub.
class UpdateDialog extends StatelessWidget {
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateDialog({
    super.key,
    required this.latestVersion,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  Future<void> _openDownload(BuildContext context) async {
    final uri = Uri.parse(downloadUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok && context.mounted) Navigator.of(context).pop();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open download link'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      title: null,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header icon
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tomatoRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rocket_launch_rounded,
                color: tomatoRed,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Title
          Center(
            child: Text(
              'New Update Available',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Meal Streak v$latestVersion',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tomatoRed,
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Release notes
          Text(
            "WHAT'S NEW",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: mutedColor,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                releaseNotes,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Later',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: mutedColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => _openDownload(context),
                icon: const Icon(Icons.download_rounded,
                    color: Colors.white, size: 18),
                label: const Text(
                  'Update Now',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tomatoRed,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
