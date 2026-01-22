import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../installer/installer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const Color kBg = Color(0xFF05070A);
const Color kSurface = Color(0xFF0A0C10);
const Color kSurfaceAlt = Color(0xFF07090D);

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, Future<List<dynamic>>> _panelFutures = {};
  StreamSubscription? _packageSub;

  late final Installer installer;

  void _forceRefresh() {
    _panelFutures.clear();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();

    installer = Installer(
      alert: _alert,
      forceRefresh: _forceRefresh,
    );

    _packageSub = Installer.packageEvents.receiveBroadcastStream().listen(
          (event) async {
        if (event is Map) {
          final pkg = event['package'];
          final status = event['status'];
          final action = event['action'];

          if (pkg is String && status == 'success') {
            if (action == 'install') {
              final repo = _repoForPackage(pkg);
              await installer.saveLatestVersion(pkg, repo);
            }

            if (action == 'uninstall') {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('version_$pkg');
            }

            _forceRefresh();
          }
        }
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _packageSub?.cancel();
    super.dispose();
  }

  String _repoForPackage(String package) {
    switch (package) {
      case 'com.colourswift.cssecurity':
        return 'phsycologicalFudge/ColourSwift_AV';
      case 'com.colourswift.securefiles':
        return 'phsycologicalFudge/CS-Secure-Files';
      default:
        throw Exception('Unknown package: $package');
    }
  }

  Future<List<dynamic>> _loadPanelState(String package, String repo) {
    return _panelFutures.putIfAbsent(
      package,
          () => Future.wait([
        installer.isPackageInstalledSystem(package),
        installer.getInstalledVersion(package),
        installer.getLatestVersion(repo),
      ]),
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
    if (mounted) setState(() {});
  }

  Future<void> _showAutoUpdateDialog() async {
    final enabled = await _isAutoUpdateEnabled();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Stealth Updater',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'When enabled, this manager will periodically check GitHub '
              'for new releases and update installed apps using Shizuku.\n\n'
              '• App must be installed via Shizuku',
          style: TextStyle(color: Colors.white70, height: 1.25),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _toggleAutoUpdate();
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(enabled ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
  }

  void _alert(String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0E1621),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Text(text, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _appPanel({
    required String name,
    required String description,
    required String iconPath,
    required String repo,
    required String package,
  }) {
    return FutureBuilder<List<dynamic>>(
      future: _loadPanelState(package, repo),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.length < 3) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Container(
              height: 156,
              decoration: BoxDecoration(
                color: const Color(0xFF0E1621),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(.06)),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 24,
                    spreadRadius: 0,
                    color: Colors.black.withOpacity(.35),
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        }

        final installed = snap.data![0] == true;
        final installedVersion = snap.data![1] as String?;
        final latestVersion = snap.data![2] as String?;

        final hasUpdate = installed &&
            installedVersion != null &&
            latestVersion != null &&
            installer.hasUpdate(installedVersion, latestVersion);

        final primaryLabel = installed ? (hasUpdate ? 'Update' : 'Open') : 'Install';

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(.045)),
              color: kSurface,
              boxShadow: [
                BoxShadow(
                  blurRadius: 28,
                  spreadRadius: 0,
                  color: Colors.black.withOpacity(.42),
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(.06)),
                        ),
                        child: Image.asset(iconPath, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            description,
                            style: TextStyle(
                              color: Colors.white.withOpacity(.72),
                              height: 1.15,
                              fontSize: 13.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.06)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          installedVersion != null ? 'Installed: $installedVersion' : 'Installed: Not installed',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.72),
                            fontSize: 12.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          latestVersion != null ? 'Latest: $latestVersion' : 'Latest: Unknown',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.55),
                            fontSize: 12.8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 14 * 2 - 18 * 2 - 10) / 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (!installed) {
                            installer.installNormal(repo, package);
                          } else if (hasUpdate) {
                            installer.installNormal(repo, package);
                          } else {
                            installer.openApp(package);
                          }
                        },
                        icon: Icon(
                          installed ? (hasUpdate ? Icons.system_update_alt_rounded : Icons.open_in_new_rounded) : Icons.download_rounded,
                          size: 18,
                        ),
                        label: Text(primaryLabel),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.of(context).size.width - 14 * 2 - 18 * 2 - 10) / 2,
                      child: FilledButton.tonalIcon(
                        onPressed: () => installer.installWithShizuku(repo, package),
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Shizuku'),
                      ),
                    ),
                    if (installed)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withOpacity(.55)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => installer.uninstall(package),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Uninstall'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _downloadOverlay() {
    return ValueListenableBuilder<DownloadState?>(
      valueListenable: installer.download,
      builder: (_, state, __) {
        if (state == null) return const SizedBox.shrink();
        final progress = state.indeterminate ? null : (state.total > 0 ? state.received / state.total : null);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(top: BorderSide(color: Colors.white.withOpacity(.08))),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                color: Colors.black.withOpacity(.35),
                offset: const Offset(0, -10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(value: progress, strokeWidth: 3),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  state.stage,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              if (!state.indeterminate && state.total > 0)
                Text(
                  '${((state.received / state.total) * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white.withOpacity(.7), fontWeight: FontWeight.w700),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0C10),
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(.045))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'AvarionX Manager',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.system_update_alt_rounded, color: Colors.white70),
                    tooltip: 'Stealth Updater',
                    onPressed: _showAutoUpdateDialog,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    tooltip: 'Refresh',
                    onPressed: _forceRefresh,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                children: [
                  _appPanel(
                    name: 'AvarionX',
                    description: 'Powerful malware protection. Shizuku unlocks system watcher.',
                    iconPath: 'assets/apps/css_security2.png',
                    repo: 'phsycologicalFudge/ColourSwift_AV',
                    package: 'com.colourswift.cssecurity',
                  ),
                  _appPanel(
                    name: 'CS Secure Files',
                    description: 'Secure file manager.',
                    iconPath: 'assets/apps/css_file_manager2.png',
                    repo: 'phsycologicalFudge/CS-Secure-Files',
                    package: 'com.colourswift.securefiles',
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
}
