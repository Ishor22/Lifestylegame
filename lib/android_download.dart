import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Stable link that always points to the newest published APK.
const String kApkDownloadUrl =
    'https://github.com/Ishor22/Lifestylegame/releases/latest/download/my-life-business-tycoon.apk';

/// Used to confirm an APK is really published before showing the download button.
const String _latestReleaseApi = 'https://api.github.com/repos/Ishor22/Lifestylegame/releases/latest';
const String _apkFileName = 'my-life-business-tycoon.apk';

enum _ApkStatus { checking, available, comingSoon }

/// Home-page card that offers the Android APK once it has been published.
/// Until then (or if the check fails) it shows a Coming Soon message instead of a broken button.
class AndroidDownloadCard extends StatefulWidget {
  const AndroidDownloadCard({super.key});

  @override
  State<AndroidDownloadCard> createState() => _AndroidDownloadCardState();
}

class _AndroidDownloadCardState extends State<AndroidDownloadCard> {
  _ApkStatus _status = _ApkStatus.checking;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    var status = _ApkStatus.comingSoon;
    try {
      final res = await http
          .get(Uri.parse(_latestReleaseApi), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final assets = (data['assets'] as List?) ?? const [];
        final published = assets.any((a) => a is Map && a['name'] == _apkFileName);
        if (published) status = _ApkStatus.available;
      }
    } catch (_) {
      // Network or API problem: keep the Coming Soon message.
    }
    if (mounted) setState(() => _status = status);
  }

  Future<void> _download() async {
    await launchUrl(Uri.parse(kApkDownloadUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = _status == _ApkStatus.available;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Download Android App',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'My Life: Business Tycoon — start with nothing, find a job, earn money, '
            'build your career and grow your business. Take your life with you on Android.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 16),
          if (available)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: scheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _download,
              icon: const Icon(Icons.download),
              label: const Text('Download for Android'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white24,
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: null,
              icon: const Icon(Icons.hourglass_empty),
              label: Text(_status == _ApkStatus.checking ? 'Checking…' : 'Coming Soon'),
            ),
          const SizedBox(height: 10),
          Text(
            available
                ? 'Android may ask you to allow installs from your browser: open Settings → Apps → '
                    'your browser → Install unknown apps, then turn it on.'
                : 'The Android app is being prepared. Check back soon.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
