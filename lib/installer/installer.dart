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

  static const String kMirrorUrl = 'https://colourswift.com/manager/mirror.json';

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

  Future<Map<String, dynamic>> _fetchMirror() async {
    final res = await http.get(
      Uri.parse(kMirrorUrl),
      headers: {
        'User-Agent': 'AvarionX-Manager',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Mirror error: ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception('Mirror invalid JSON');
    }

    final apps = decoded['apps'];
    if (apps is! Map) {
      throw Exception('Mirror missing apps');
    }

    return apps.cast<String, dynamic>();
  }

  Map<String, dynamic>? _mirrorEntryForRepo(Map<String, dynamic> apps, String repo) {
    final raw = apps[repo];
    if (raw is Map) return raw.cast<String, dynamic>();
    return null;
  }

  String? _mirrorLatestVersion(Map<String, dynamic> entry) {
    final v = entry['latestVersion'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Map<String, dynamic>? _mirrorDownloads(Map<String, dynamic> entry) {
    final d = entry['downloads'];
    if (d is Map) return d.cast<String, dynamic>();
    return null;
  }

  Map<String, dynamic>? _mirrorPickDownload(Map<String, dynamic> downloads, String abi) {
    final direct = downloads[abi];
    if (direct is Map) return direct.cast<String, dynamic>();

    final uni = downloads['universal'];
    if (uni is Map) return uni.cast<String, dynamic>();

    final any = downloads['any'];
    if (any is Map) return any.cast<String, dynamic>();

    return null;
  }

  Uri _mirrorDownloadUrl(Map<String, dynamic> picked) {
    final url = picked['url'];
    if (url is! String || url.trim().isEmpty) {
      throw Exception('Mirror missing download url');
    }
    return Uri.parse(url.trim());
  }

  String _mirrorFileName(Map<String, dynamic> picked, Uri url) {
    final name = picked['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    if (url.pathSegments.isNotEmpty) return Uri.decodeComponent(url.pathSegments.last);
    return 'app.apk';
  }

  Future<File> downloadApk(String repo, {bool clearOverlayOnDone = true}) async {
    download.value = DownloadState(stage: 'Fetching release info');

    final apps = await _fetchMirror();
    final entry = _mirrorEntryForRepo(apps, repo);
    if (entry == null) {
      download.value = null;
      throw Exception('Mirror missing repo: $repo');
    }

    final abi = getPreferredAbi();
    final downloads = _mirrorDownloads(entry);
    if (downloads == null) {
      download.value = null;
      throw Exception('Mirror missing downloads for repo: $repo');
    }

    final picked = _mirrorPickDownload(downloads, abi);
    if (picked == null) {
      download.value = null;
      throw Exception('No APK found for ABI: $abi');
    }

    final apkUrl = _mirrorDownloadUrl(picked);
    final name = _mirrorFileName(picked, apkUrl);

    final req = http.Request('GET', apkUrl);
    req.headers['User-Agent'] = 'AvarionX-Manager';

    final res = await http.Client().send(req);

    final state = DownloadState(
      stage: 'Downloading APK',
      indeterminate: false,
    )..total = res.contentLength ?? 0;

    download.value = state;

    final dir = await getExternalStorageDirectory();
    final file = File('${dir!.path}/$name');
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
    try {
      final apps = await _fetchMirror();
      final entry = _mirrorEntryForRepo(apps, repo);
      if (entry == null) return;

      final raw = _mirrorLatestVersion(entry);
      if (raw == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('version_$package', normalizeTag(raw));
    } catch (_) {}
  }

  Future<String?> getLatestVersion(String repo) async {
    try {
      final apps = await _fetchMirror();
      final entry = _mirrorEntryForRepo(apps, repo);
      if (entry == null) return null;

      final raw = _mirrorLatestVersion(entry);
      if (raw == null) return null;

      return normalizeTag(raw);
    } catch (_) {
      return null;
    }
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