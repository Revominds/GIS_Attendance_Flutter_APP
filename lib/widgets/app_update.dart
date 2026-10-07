// Shared "update available" dialog: shows version + notes, downloads the
// APK with progress, then launches the system installer which installs
// OVER the current app (data kept — no uninstall/reinstall needed).

import 'package:flutter/material.dart';
import 'package:gis_attendance/services/update_service.dart';

class AppUpdate {
  /// Shows the update prompt. [onSkip] is called when the user taps Later
  /// (only offered when the update isn't mandatory).
  static Future<void> prompt(
    BuildContext context,
    UpdateInfo info, {
    bool allowLater = true,
    VoidCallback? onSkip,
  }) {
    final canDefer = allowLater && !info.mandatory;
    return showDialog(
      context: context,
      barrierDismissible: canDefer,
      builder: (ctx) => _UpdateDialog(
        info: info,
        canDefer: canDefer,
        onSkip: onSkip,
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final bool canDefer;
  final VoidCallback? onSkip;

  const _UpdateDialog({
    required this.info,
    required this.canDefer,
    this.onSkip,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  bool _launched = false;

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await UpdateService.downloadAndInstall(
        widget.info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _launched = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.info.mandatory
          ? 'Update required (${widget.info.version})'
          : 'Update available (${widget.info.version})'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.info.notes.isNotEmpty) Text(widget.info.notes),
          if (widget.info.notes.isNotEmpty) const SizedBox(height: 12),
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Downloading… ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Starting download…',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          if (_launched)
            const Text(
              'Download complete — tap Install in the system prompt to update. Your data is kept.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          if (_error != null)
            Text('Failed: $_error',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
      actions: [
        if (widget.canDefer && !_downloading && !_launched)
          TextButton(
            onPressed: () {
              widget.onSkip?.call();
              Navigator.pop(context);
            },
            child: const Text('Later'),
          ),
        if (!_launched)
          FilledButton(
            onPressed: _downloading ? null : _downloadAndInstall,
            child: Text(_downloading
                ? 'Downloading…'
                : _error != null
                    ? 'Retry'
                    : 'Download & Install'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
      ],
    );
  }
}
