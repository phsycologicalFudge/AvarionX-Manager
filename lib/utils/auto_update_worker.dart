import 'dart:convert';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

const MethodChannel _shizuku =
MethodChannel('colourswift_manager/shizuku');

class ManagedApp {
  final String packageName;
  final String repo;

  const ManagedApp(this.packageName, this.repo);
}

const managedApps = [
  ManagedApp(
    'com.colourswift.security',
    'phsycologicalFudge/ColourSwift_AV',
  ),
  ManagedApp(
    'com.colourswift.files',
    'phsycologicalFudge/CS-Secure-Files',
  ),
];

String getPreferredAbi() {
  final v = Platform.version.toLowerCase();
  if (v.contains('arm64')) return 'arm64-v8a';
  if (v.contains('armv7')) return 'armeabi-v7a';
  if (v.contains('x86_64')) return 'x86_64';
  return 'arm64-v8a';
}

String normalizeTag(String tag) {
  return tag.startsWith('v') ? tag.substring(1) : tag;
}

@pragma('vm:entry-point')
void autoUpdateWorker() {
  Workmanager().executeTask((task, inputData) async {
    if (!Platform.isAndroid) return true;

    final shizukuOk =
        await _shizuku.invokeMethod<bool>('ping') ?? false;
    if (!shizukuOk) return true;

    final hasPerm =
        await _shizuku.invokeMethod<bool>('hasPermission') ?? false;
    if (!hasPerm) return true;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_update_enabled') ?? false;
    if (!enabled) return true;

    for (final app in managedApps) {
      try {
        final installed =
            await _shizuku.invokeMethod<bool>(
              'isInstalled',
              {'package': app.packageName},
            ) ??
                false;

        if (!installed) continue;

        final storedVersion =
        prefs.getString('version_${app.packageName}');
        if (storedVersion == null) continue;

        final releaseRes = await http.get(
          Uri.parse(
            'https://api.github.com/repos/${app.repo}/releases/latest',
          ),
        );

        if (releaseRes.statusCode != 200) continue;

        final release = jsonDecode(releaseRes.body);
        if (release['prerelease'] == true) continue;

        final rawTag = release['tag_name'];
        if (rawTag == null || rawTag is! String) continue;

        final latestVersion = normalizeTag(rawTag);
        if (latestVersion == storedVersion) continue;

        final assets = release['assets'] as List;
        final abi = getPreferredAbi();

        final apk = assets.firstWhere(
              (a) =>
          a['name'].toString().endsWith('.apk') &&
              a['name'].toString().contains(abi),
          orElse: () => null,
        );

        if (apk == null) continue;

        final url = apk['browser_download_url'];
        final res = await http.get(Uri.parse(url));
        if (res.statusCode != 200) continue;

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${apk['name']}');
        await file.writeAsBytes(res.bodyBytes);

        await _shizuku.invokeMethod(
          'installApk',
          {'path': file.path},
        );

        await _shizuku.invokeMethod(
          'injectCert',
          {
            'package': app.packageName,
            'content': 'shizuku=enabled',
          },
        );

        await prefs.setString(
          'version_${app.packageName}',
          latestVersion,
        );

        await file.delete();
      } catch (_) {}
    }

    return true;
  });
}
