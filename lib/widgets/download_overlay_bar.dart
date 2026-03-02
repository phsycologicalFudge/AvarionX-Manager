import 'package:flutter/material.dart';
import '../installer/installer.dart';

class DownloadOverlayBar extends StatelessWidget {
  final DownloadState state;

  const DownloadOverlayBar({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final progress = state.indeterminate ? null : (state.total > 0 ? state.received / state.total : null);

    return SafeArea(
      top: false,
      child: Container(
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            if (!state.indeterminate && state.total > 0)
              Text(
                '${((state.received / state.total) * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white.withOpacity(.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}