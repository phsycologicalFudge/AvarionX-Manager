import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_apps/device_apps.dart';

class DownloadState {
  int received = 0;
  int total = 0;
  StreamSubscription<List<int>>? sub;
  Completer<File> completer = Completer<File>();
  String stage;
  bool indeterminate;

  DownloadState({
    required this.stage,
    this.indeterminate = true,
  });
}

class Installer {
  Installer({
    required this.alert,
    required this.forceRefresh,
  });

  final void Function(String text) alert;
  final void Function() forceRefresh;

  static const MethodChannel shizuku = MethodChannel('colourswift_manager/shizuku');
  static const EventChannel packageEvents = EventChannel('colourswift_manager/package_events');

  final ValueNotifier<DownloadState?> download = ValueNotifier<DownloadState?>(null);

  void setStage(String text, {bool indeterminate = true}) {
    download.value = DownloadState(
      stage: text,
      indeterminate: indeterminate,
    );
  }

  String getPreferredAbi() {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armv7')) return 'armeabi-v7a';
    if (v.contains('x86_64')) return 'x86_64';
    return 'arm64-v8a';
  }

  Future<bool> isShizukuAvailable() async {
    return await shizuku.invokeMethod<bool>('ping') ?? false;
  }

  Future<bool> hasShizukuPermission() async {
    return await shizuku.invokeMethod<bool>('hasPermission') ?? false;
  }

  Future<void> requestShizukuPermission() async {
    await shizuku.invokeMethod('requestPermission');
  }

  Future<bool> isPackageInstalledSystem(String package) async {
    return await shizuku.invokeMethod<bool>(
      'packageInstalledSystem',
      {'package': package},
    ) ??
        false;
  }

  Future<String?> getPackageVersionNameSystem(String package) async {
    final v = await shizuku.invokeMethod<String>(
      'getPackageVersionName',
      {'package': package},
    );
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<File> downloadApk(String repo, {bool clearOverlayOnDone = true}) async {
    download.value = DownloadState(stage: 'Fetching release info');

    final releaseRes = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      headers: {
        'User-Agent': 'AvarionX-Manager',
        'Accept': 'application/vnd.github+json',
      },
    );

    if (releaseRes.statusCode != 200) {
      download.value = null;
      throw Exception('GitHub API error: ${releaseRes.statusCode}');
    }

    final release = jsonDecode(releaseRes.body);

    final assets = release['assets'];
    if (assets is! List || assets.isEmpty) {
      download.value = null;
      throw Exception('No release assets found');
    }

    final abi = getPreferredAbi();
    Map<String, dynamic>? apk;

    for (final a in assets) {
      if (a is Map &&
          a['name'] is String &&
          a['name'].toString().endsWith('.apk') &&
          a['name'].toString().contains(abi)) {
        apk = a.cast<String, dynamic>();
        break;
      }
    }

    if (apk == null) {
      download.value = null;
      throw Exception('No APK found for ABI: $abi');
    }

    final req = http.Request(
      'GET',
      Uri.parse(apk['browser_download_url']),
    );

    final res = await http.Client().send(req);

    final state = DownloadState(
      stage: 'Downloading APK',
      indeterminate: false,
    )..total = res.contentLength ?? 0;

    download.value = state;

    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/${apk['name']}');
    final sink = file.openWrite();

    state.sub = res.stream.listen(
          (chunk) {
        sink.add(chunk);
        state.received += chunk.length;
        download.notifyListeners();
      },
      onDone: () async {
        await sink.close();
        if (clearOverlayOnDone) {
          download.value = null;
        }
        state.completer.complete(file);
      },
      onError: (e) async {
        await sink.close();
        download.value = null;
        state.completer.completeError(e);
      },
      cancelOnError: true,
    );

    return state.completer.future;
  }

  Future<void> installNormal(String repo, String package) async {
    try {
      final file = await downloadApk(repo);

      await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
    } catch (e) {
      download.value = null;
      alert(e.toString());
    }
  }

  Future<void> installWithShizuku(String repo, String package) async {
    try {
      if (!await isShizukuAvailable()) {
        alert('Shizuku is not running');
        return;
      }

      if (!await hasShizukuPermission()) {
        await requestShizukuPermission();
        alert('Grant Shizuku permission, then tap again');
        return;
      }

      final file = await downloadApk(repo, clearOverlayOnDone: false);

      download.value = DownloadState(stage: 'Signing APK');

      await shizuku.invokeMethod(
        'installApk',
        {'path': file.path},
      );

      download.value = DownloadState(stage: 'Finalising install');

      await injectCert(package);

      download.value = null;
    } catch (e) {
      download.value = null;
      alert(e.toString());
    }
  }

  Future<void> uninstall(String package) async {
    try {
      await shizuku.invokeMethod(
        'uninstallApk',
        {'package': package},
      );
    } catch (e) {
      alert(e.toString());
    }
  }

  Future<void> openApp(String package) async {
    final opened = await DeviceApps.openApp(package);
    if (!opened) {
      alert('Unable to open app');
    }
  }

  String? cleanVersion(String? v) {
    if (v == null) return null;
    var s = v.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v')) s = s.substring(1);
    final cutAt = <String>[' ', '(', '+'];
    for (final c in cutAt) {
      final i = s.indexOf(c);
      if (i > 0) s = s.substring(0, i);
    }
    s = s.trim();
    return s.isEmpty ? null : s;
  }

  int compareVersions(String installed, String latest) {
    var a = cleanVersion(installed);
    var b = cleanVersion(latest);

    if (a == null || b == null) return 0;

    a = a.split('-').first.trim();
    b = b.split('-').first.trim();

    List<int> parseParts(String s) {
      return s.split('.').map((p) {
        final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
        return int.tryParse(digits) ?? 0;
      }).toList();
    }

    final ap = parseParts(a);
    final bp = parseParts(b);
    final n = ap.length > bp.length ? ap.length : bp.length;

    for (var i = 0; i < n; i++) {
      final av = i < ap.length ? ap[i] : 0;
      final bv = i < bp.length ? bp[i] : 0;
      if (av != bv) return av > bv ? 1 : -1;
    }

    return 0;
  }

  bool hasUpdate(String installed, String latest) {
    return compareVersions(installed, latest) < 0;
  }

  String normalizeTag(String tag) {
    return tag.startsWith('v') ? tag.substring(1) : tag;
  }

  Future<void> saveLatestVersion(String package, String repo) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      headers: {
        'User-Agent': 'AvarionX-Manager',
        'Accept': 'application/vnd.github+json',
      },
    );

    if (res.statusCode != 200) return;

    final release = jsonDecode(res.body);
    if (release['prerelease'] == true) return;

    final raw = release['tag_name'];
    if (raw is! String) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('version_$package', normalizeTag(raw));
  }

  Future<String?> getLatestVersion(String repo) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      headers: {
        'User-Agent': 'AvarionX-Manager',
        'Accept': 'application/vnd.github+json',
      },
    );

    if (res.statusCode != 200) return null;

    final release = jsonDecode(res.body);
    if (release['prerelease'] == true) return null;

    final raw = release['tag_name'];
    if (raw is! String) return null;

    return normalizeTag(raw);
  }

  Future<String?> getInstalledVersion(String package) async {
    final real = await getPackageVersionNameSystem(package);
    if (real != null) return real;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('version_$package');
  }

  Future<void> injectCert(String package) async {
    await shizuku.invokeMethod(
      'injectCert',
      {'package': package, 'content': 'shizuku=enabled'},
    );
  }
}
