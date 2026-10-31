import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import 'device_tile.dart';

class TransferList extends StatelessWidget {
  const TransferList({
    super.key,
    required this.transfers,
    required this.onDismiss,
    required this.onOpenFolder,
  });

  final List<Transfer> transfers;
  final ValueChanged<Transfer> onDismiss;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final visible = transfers.take(3).toList();
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in visible)
            Padding(
              key: ValueKey(t.id),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: EntranceCard(
                child: TransferCard(
                  transfer: t,
                  onDismiss: () => onDismiss(t),
                  onOpenFolder: onOpenFolder,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EntranceCard extends StatelessWidget {
  const EntranceCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
        ),
        child: child,
      );
}

class TransferCard extends StatelessWidget {
  const TransferCard({
    super.key,
    required this.transfer,
    required this.onDismiss,
    required this.onOpenFolder,
  });

  final Transfer transfer;
  final VoidCallback onDismiss;
  final VoidCallback onOpenFolder;

  String get _title {
    final t = transfer;
    final what = t.fileNames.length == 1 ? t.fileNames.first : '${t.fileNames.length} files';
    final outgoing = t.direction == TransferDirection.outgoing;
    return switch (t.status) {
      TransferStatus.waiting => outgoing ? 'Waiting for ${t.peerName} to accept…' : 'Getting ready…',
      TransferStatus.active => outgoing ? 'Sending $what to ${t.peerName}' : 'Receiving $what from ${t.peerName}',
      TransferStatus.done => outgoing ? 'Sent $what to ${t.peerName}' : 'Got $what from ${t.peerName}',
      _ => t.error ?? 'Something went wrong',
    };
  }

  String get _subtitle {
    final t = transfer;
    switch (t.status) {
      case TransferStatus.active:
        return '${formatBytes(t.doneBytes)} of ${formatBytes(t.totalBytes)}';
      case TransferStatus.done:
        if (t.direction == TransferDirection.incoming) {
          return Platform.isIOS ? 'Saved in Files › Sushi Roll' : 'Saved to your Sushi Roll folder';
        }
        return formatBytes(t.totalBytes);
      case TransferStatus.waiting:
        return formatBytes(t.totalBytes);
      default:
        return t.fileNames.length == 1 ? t.fileNames.first : '${t.fileNames.length} files';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final t = transfer;
    final failed = t.status == TransferStatus.failed ||
        t.status == TransferStatus.declined ||
        t.status == TransferStatus.cancelled;
    final canOpen = t.status == TransferStatus.done &&
        t.direction == TransferDirection.incoming &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                child: child,
              ),
              child: switch (t.status) {
                TransferStatus.done => _StatusDot(
                    key: const ValueKey('done'), icon: Icons.check_rounded, color: Palette.wasabi),
                _ when failed => _StatusDot(
                    key: const ValueKey('fail'), icon: Icons.close_rounded, color: scheme.error),
                _ => FittedBox(
                    key: const ValueKey('device'),
                    child: DeviceAvatar(platform: t.peerPlatform, size: 44),
                  ),
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (t.status == TransferStatus.active || t.status == TransferStatus.waiting)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: t.progress),
                      duration: const Duration(milliseconds: 250),
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: t.status == TransferStatus.waiting ? null : v,
                        minHeight: 6,
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                if (t.status == TransferStatus.active || t.status == TransferStatus.waiting)
                  const SizedBox(height: 4),
                Text(_subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                    )),
              ],
            ),
          ),
          if (canOpen)
            TextButton(onPressed: onOpenFolder, child: const Text('Open')),
          IconButton(
            tooltip: t.isFinished ? 'Dismiss' : 'Cancel',
            onPressed: t.isFinished ? onDismiss : t.onCancel,
            icon: Icon(t.isFinished ? Icons.close_rounded : Icons.stop_circle_outlined, size: 22),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
        child: Icon(icon, color: color),
      );
}
