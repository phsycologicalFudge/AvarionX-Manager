import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../installer/installer.dart';
import '../models/app_meta.dart';
import '../widgets/no_glow_scroll_behavior.dart';
import '../widgets/download_overlay_bar.dart';
import 'app_details_screen.dart';

const Color kBg = Color(0xFF05070A);
const Color kSurface = Color(0xFF0A0C10);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, Future<List<dynamic>>> _rowFutures = {};
  StreamSubscription? _packageSub;

  late final Installer installer;

  void _forceRefresh() {
    _rowFutures.clear();
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
      case 'com.colourswift.avarionxvpn':
        return 'phsycologicalFudge/AvarionX-VPN';
      case 'com.colourswift.securefiles':
        return 'phsycologicalFudge/CS-Secure-Files';
      default:
        throw Exception('Unknown package: $package');
    }
  }

  Future<List<dynamic>> _loadRowState(AppMeta app) {
    return _rowFutures.putIfAbsent(
      app.package,
          () => Future.wait([
        installer.isPackageInstalledSystem(app.package),
        installer.getInstalledVersion(app.package),
        installer.getLatestVersion(app.repo),
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
          'When enabled, this manager will periodically check for new releases and update installed apps using Shizuku.\n\n'
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

  Widget _leadingIcon(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(.06)),
        ),
        child: Image.asset(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.apps_rounded, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _appRow(AppMeta app) {
    return FutureBuilder<List<dynamic>>(
      future: _loadRowState(app),
      builder: (context, snap) {
        final installed = snap.data != null && snap.data!.isNotEmpty && snap.data![0] == true;
        final installedVersion = snap.data != null && snap.data!.length >= 2 ? snap.data![1] as String? : null;
        final latestVersion = snap.data != null && snap.data!.length >= 3 ? snap.data![2] as String? : null;

        final hasUpdate = installed &&
            installedVersion != null &&
            latestVersion != null &&
            installer.hasUpdate(installedVersion, latestVersion);

        final status = app.archived
            ? 'Archived'
            : installed
            ? (hasUpdate ? 'Update available' : 'Installed')
            : 'Not installed';

        return InkWell(
          splashFactory: NoSplash.splashFactory,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          highlightColor: Colors.transparent,
          onTap: () async {
            await Navigator.of(context).push(
              PageRouteBuilder(
                opaque: true,
                pageBuilder: (_, __, ___) {
                  return Material(
                    color: kBg,
                    child: AppDetailsScreen(
                      meta: app,
                      installer: installer,
                    ),
                  );
                },
                transitionsBuilder: (_, animation, __, child) {
                  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
                  return FadeTransition(opacity: curved, child: child);
                },
              ),
            );
            _forceRefresh();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                _leadingIcon(app.iconPath),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.70),
                          fontSize: 12.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(.60)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = <AppMeta>[
      const AppMeta(
        name: 'AvarionX',
        description: 'Powerful malware protection. Shizuku unlocks system watcher.',
        iconPath: 'assets/apps/css_security2.png',
        heroImagePath: 'assets/apps/css_security2.png',
        screenshots: [
          'assets/screenshots/avHome.png',
          'assets/screenshots/avScan.png',
          'assets/screenshots/avClean.jpg',
        ],
        repo: 'phsycologicalFudge/ColourSwift_AV',
        package: 'com.colourswift.cssecurity',
        archived: false,
      ),
      const AppMeta(
        name: 'AvarionX VPN',
        description: 'A VPN with DNS filtering, powered by vx-Link.',
        iconPath: 'assets/apps/avarionx.png',
        heroImagePath: 'assets/apps/avarionx.png',
        screenshots: [
          'assets/screenshots/vpnConnected.jpg',
          'assets/screenshots/vpnSettings.jpg',
          'assets/screenshots/vpnDNS.jpg',
        ],
        repo: 'phsycologicalFudge/AvarionX-VPN',
        package: 'com.colourswift.avarionxvpn',
        archived: false,
      ),
      const AppMeta(
        name: 'CS Secure Files',
        description: 'Secure file manager.',
        iconPath: 'assets/apps/css_file_manager2.png',
        heroImagePath: 'assets/apps/css_file_manager2.png',
        screenshots: [
          'assets/screenshots/files_1.png',
        ],
        repo: 'phsycologicalFudge/CS-Secure-Files',
        package: 'com.colourswift.securefiles',
        archived: true,
      ),
    ];

    return Scaffold(
      backgroundColor: kBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: SafeArea(
          child: ValueListenableBuilder<DownloadState?>(
            valueListenable: installer.download,
            builder: (_, state, __) {
              final bottomPad = state == null ? 10.0 : 92.0;

              return Stack(
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 12, 18),
                        decoration: BoxDecoration(
                          color: kSurface,
                          border: Border(
                            bottom: BorderSide(color: Colors.white.withOpacity(.045)),
                          ),
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
                        child: ScrollConfiguration(
                          behavior: const NoGlowScrollBehavior(),
                          child: ListView.separated(
                            padding: EdgeInsets.only(top: 6, bottom: bottomPad),
                            itemCount: apps.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: Colors.white.withOpacity(.06),
                              indent: 16,
                              endIndent: 16,
                            ),
                            itemBuilder: (_, i) => _appRow(apps[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DownloadOverlayBar(state: state),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}