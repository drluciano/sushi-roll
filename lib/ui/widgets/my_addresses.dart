import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/protocol.dart';

/// "Here's how to reach me": this device's local and Tailscale addresses as
/// small pills, each tap-to-copy. Shown where the main screen used to say
/// "Looking around…" so it's easy to add this device from the other one.
class MyAddresses extends StatelessWidget {
  const MyAddresses({
    super.key,
    required this.lan,
    required this.tailscale,
    required this.tailscaleName,
    required this.port,
  });

  final String? lan;
  final String? tailscale;
  final String? tailscaleName;
  final int port;

  bool get isEmpty => lan == null && tailscale == null && tailscaleName == null;

  /// What the other device should type. The port only matters when it isn't
  /// the default, which happens if something else already took 47100.
  String _typed(String host) {
    if (port == kDefaultPort) return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied $text')));
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (lan != null) ('Local', _typed(lan!)),
      if (tailscale != null) ('Tailscale', _typed(tailscale!)),
      if (tailscaleName != null) ('MagicDNS', _typed(tailscaleName!)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (label, value)) in rows.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _Pill(
              key: ValueKey(label),
              label: label,
              value: value,
              onTap: () => _copy(context, value),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Tooltip(
      message: 'Tap to copy',
      child: Material(
        color: primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.copy_rounded, size: 16, color: primary.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
