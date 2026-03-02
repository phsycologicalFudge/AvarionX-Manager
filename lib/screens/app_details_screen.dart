import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../installer/installer.dart';
import '../models/app_meta.dart';
import '../widgets/no_glow_scroll_behavior.dart';
import '../widgets/download_overlay_bar.dart';

const Color kBg = Color(0xFF05070A);
const Color kSurface = Color(0xFF0A0C10);

class AppDetailsScreen extends StatefulWidget {
  final AppMeta meta;
  final Installer installer;

  const AppDetailsScreen({
    super.key,
    required this.meta,
    required this.installer,
  });

  @override
  State<AppDetailsScreen> createState() => _AppDetailsScreenState();
}

class _AppDetailsScreenState extends State<AppDetailsScreen> {
  Future<List<dynamic>> _load() {
    return Future.wait([
      widget.installer.isPackageInstalledSystem(widget.meta.package),
      widget.installer.getInstalledVersion(widget.meta.package),
      widget.installer.getLatestVersion(widget.meta.repo),
    ]);
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withOpacity(.82),
          fontSize: 11.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text(widget.meta.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ValueListenableBuilder<DownloadState?>(
        valueListenable: widget.installer.download,
        builder: (context, state, _) {
          final bottomPad = state == null ? 18.0 : 92.0;

          return Stack(
            children: [
              FutureBuilder<List<dynamic>>(
                future: _load(),
                builder: (context, snap) {
                  final installed = snap.data != null && snap.data!.isNotEmpty && snap.data![0] == true;
                  final installedVersion = snap.data != null && snap.data!.length >= 2 ? snap.data![1] as String? : null;
                  final latestVersion = snap.data != null && snap.data!.length >= 3 ? snap.data![2] as String? : null;

                  final hasUpdate = installed &&
                      installedVersion != null &&
                      latestVersion != null &&
                      widget.installer.hasUpdate(installedVersion, latestVersion);

                  final status = widget.meta.archived
                      ? 'Archived'
                      : installed
                      ? (hasUpdate ? 'Update available' : 'Installed')
                      : 'Not installed';

                  final primaryLabel = installed ? (hasUpdate ? 'Update' : 'Open') : 'Install';

                  return ScrollConfiguration(
                    behavior: const NoGlowScrollBehavior(),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPad),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.06),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withOpacity(.06)),
                                ),
                                child: Image.asset(
                                  widget.meta.iconPath,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.apps_rounded, color: Colors.white70),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.meta.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      _chip(status),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.meta.description,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.75),
                            fontSize: 13.6,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (installedVersion != null || latestVersion != null)
                          Text(
                            'Installed: ${installedVersion ?? 'Not installed'}  •  Latest: ${latestVersion ?? 'Unknown'}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.55),
                              fontSize: 12.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 240,
                          child: ScrollConfiguration(
                            behavior: const NoGlowScrollBehavior(),
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              itemCount: widget.meta.screenshots.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final path = widget.meta.screenshots[i];

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: AspectRatio(
                                    aspectRatio: 9 / 19.5,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(.03),
                                        border: Border.all(color: Colors.white.withOpacity(.06)),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Image.asset(
                                        path,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Icon(
                                            Icons.image_not_supported_outlined,
                                            color: Colors.white.withOpacity(.6),
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  if (!installed) {
                                    await widget.installer.installNormal(widget.meta.repo, widget.meta.package);
                                  } else if (hasUpdate) {
                                    await widget.installer.installNormal(widget.meta.repo, widget.meta.package);
                                  } else {
                                    await widget.installer.openApp(widget.meta.package);
                                  }
                                  if (mounted) setState(() {});
                                },
                                child: Text(primaryLabel),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: () async {
                                  await widget.installer.installWithShizuku(widget.meta.repo, widget.meta.package);
                                  if (mounted) setState(() {});
                                },
                                child: const Text('Shizuku'),
                              ),
                            ),
                          ],
                        ),
                        if (installed) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withOpacity(.55)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () async {
                                await widget.installer.uninstall(widget.meta.package);
                                if (mounted) setState(() {});
                              },
                              child: const Text('Uninstall'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
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
    );
  }
}