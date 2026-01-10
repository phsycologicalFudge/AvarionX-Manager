import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DownloadState {
  int received = 0;
  int total = 0;
  bool paused = false;
  StreamSubscription<List<int>>? sub;
  Completer<File> completer = Completer<File>();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const MethodChannel _shizuku =
  MethodChannel('colourswift_manager/shizuku');

  final ValueNotifier<_DownloadState?> download =
  ValueNotifier<_DownloadState?>(null);

  String getPreferredAbi() {
    final v = Platform.version.toLowerCase();
    if (v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armv7')) return 'armeabi-v7a';
    if (v.contains('x86_64')) return 'x86_64';
    return 'arm64-v8a';
  }

  Future<bool> isShizukuAvailable() async {
    if (!Platform.isAndroid) return false;
    return await _shizuku.invokeMethod<bool>('ping') ?? false;
  }

  Future<bool> hasShizukuPermission() async {
    return await _shizuku.invokeMethod<bool>('hasPermission') ?? false;
  }

  Future<void> requestShizukuPermission() async {
    await _shizuku.invokeMethod('requestPermission');
  }

  Future<File> _downloadApk(
      BuildContext context,
      String repo,
      ) async {
    final releaseRes = await http.get(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
    );

    if (releaseRes.statusCode != 200) {
      throw 'Failed to fetch release';
    }

    final release = jsonDecode(releaseRes.body);
    final assets = release['assets'] as List;

    final abi = getPreferredAbi();
    final apk = assets.firstWhere(
          (a) =>
      a['name'].toString().endsWith('.apk') &&
          a['name'].toString().contains(abi),
    );

    final req = http.Request(
      'GET',
      Uri.parse(apk['browser_download_url']),
    );

    final res = await http.Client().send(req);

    final state = _DownloadState()
      ..total = res.contentLength ?? 0;

    download.value = state;

    final dir = await getExternalStorageDirectory();
    if (dir == null) throw 'Storage unavailable';

    final file = File('${dir.path}/${apk['name']}');
    final sink = file.openWrite();

    state.sub = res.stream.listen(
          (chunk) {
        if (state.paused) return;
        sink.add(chunk);
        state.received += chunk.length;
        download.notifyListeners();
      },
      onDone: () async {
        await sink.close();
        download.value = null;
        state.completer.complete(file);
      },
      onError: (e) async {
        await sink.close();
        download.value = null;
        if (!state.completer.isCompleted) {
          state.completer.completeError(e);
        }
      },
      cancelOnError: true,
    );

    return state.completer.future;
  }

  Future<void> installNormal(
      BuildContext context,
      String repo,
      String package,
      ) async {
    final file = await _downloadApk(context, repo);

    await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    await _saveLatestVersion(package, repo);

    if (mounted) setState(() {});
  }

  Future<void> installWithShizuku(
      BuildContext context,
      String repo,
      String package,
      ) async {
    if (!await isShizukuAvailable()) {
      _alert('Shizuku is not running');
      return;
    }

    if (!await hasShizukuPermission()) {
      await requestShizukuPermission();
      _alert('Grant Shizuku permission, then tap again');
      return;
    }

    final file = await _downloadApk(context, repo);

    await _shizuku.invokeMethod(
      'installApk',
      {'path': file.path},
    );

    await _injectCert(package);

    await _saveLatestVersion(package, repo);

    if (mounted) setState(() {});
  }

  void _alert(String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(content: Text(text)),
    );
  }

  Future<bool> _isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_update_enabled') ?? false;
  }

  Future<void> _toggleAutoUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getBool('auto_update_enabled') ?? false;
    await prefs.setBool('auto_update_enabled', !current);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !current
                ? 'Stealth Updater enabled'
                : 'Stealth Updater disabled',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _normalizeTag(String tag) {
    return tag.startsWith('v') ? tag.substring(1) : tag;
  }

  Future<void> _saveLatestVersion(
      String package,
      String repo,
      ) async {
    final res = await http.get(
      Uri.parse(
        'https://api.github.com/repos/$repo/releases/latest',
      ),
    );

    if (res.statusCode != 200) return;

    final release = jsonDecode(res.body);

    if (release['prerelease'] == true) return;

    final rawTag = release['tag_name'];
    if (rawTag == null || rawTag is! String) return;

    final version = _normalizeTag(rawTag);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('version_$package', version);
  }

  Future<void> _showAutoUpdateDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_update_enabled') ?? false;

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121822),
          title: const Text(
            'Stealth Updater',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'When enabled, this manager will periodically check GitHub for new releases and update installed apps using Shizuku.\n\n'
                '• App must be installed via Shizuku\n\n'
                'You can disable this at any time.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await prefs.setBool(
                  'auto_update_enabled',
                  !enabled,
                );
                if (mounted) Navigator.of(context).pop();
              },
              child: Text(
                enabled ? 'Disable' : 'Enable',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _getInstalledVersion(String package) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('version_$package');
  }

  Widget _installedVersionText(String package) {
    return FutureBuilder<String?>(
      future: _getInstalledVersion(package),
      builder: (context, snapshot) {
        final version = snapshot.data;
        return Text(
          version != null
              ? 'Installed version: $version'
              : 'Installed version: Not installed',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
          ),
        );
      },
    );
  }

  Future<void> _injectCert(String package) async {
    await _shizuku.invokeMethod(
      'injectCert',
      {
        'package': package,
        'content': 'shizuku=enabled',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF1A2130),
          onPressed: _showAutoUpdateDialog,
          child: const Icon(Icons.info_outline),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              color: const Color(0xFF0E1621),
              width: double.infinity,
              child: const Text(
                'AvarionX Manager',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _appPanel(
                      context,
                      name: 'AvarionX',
                      description:
                      'Powerful malware protection. Shizuku unlocks system watcher for advanced real-time protection.',
                      iconPath: 'assets/apps/css_security2.png',
                      repo: 'phsycologicalFudge/ColourSwift_AV',
                      package: 'com.colourswift.security',
                    ),
                  ),
                  Expanded(
                    child: _appPanel(
                      context,
                      name: 'CS Secure Files',
                      description:
                      'Simple file explorer. Shizuku enables access to restricted system folders in future builds.',
                      iconPath: 'assets/apps/css_file_manager2.png',
                      repo: 'phsycologicalFudge/CS-Secure-Files',
                      package: 'com.colourswift.files',
                    ),
                  ),
                ],
              ),
            ),
            _downloadOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _appPanel(
      BuildContext context, {
        required String name,
        required String description,
        required String iconPath,
        required String repo,
        required String package,
      }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121822),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    iconPath,
                    width: 56,
                    height: 56,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            _installedVersionText(package),
            const Spacer(),
            FutureBuilder<String?>(
              future: _getInstalledVersion(package),
              builder: (context, snapshot) {
                final hasVersion = snapshot.data != null;
                final label = hasVersion ? 'Update' : 'Install';

                return Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => installNormal(
                          context,
                          repo,
                          package,
                        ),
                        child: Text(label),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => installWithShizuku(
                          context,
                          repo,
                          package,
                        ),
                        child: const Text('Shizuku'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadOverlay() {
    return ValueListenableBuilder<_DownloadState?>(
      valueListenable: download,
      builder: (_, state, __) {
        if (state == null) return const SizedBox.shrink();

        final progress =
        state.total > 0 ? state.received / state.total : 0.0;

        return Container(
          padding: const EdgeInsets.all(12),
          color: const Color(0xFF0E1621),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      state.paused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      state.paused = !state.paused;
                      download.notifyListeners();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () async {
                      await state.sub?.cancel();
                      if (!state.completer.isCompleted) {
                        state.completer.completeError('Cancelled');
                      }
                      download.value = null;
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
