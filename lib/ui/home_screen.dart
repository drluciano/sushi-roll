import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/models.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/ambient.dart';
import 'widgets/device_tile.dart';
import 'widgets/send_tray.dart';
import 'widgets/transfer_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get c => widget.controller;
  StreamSubscription<IncomingOffer>? _offers;
  final Set<String> _autoDismissScheduled = {};

  bool get _mobile => Platform.isIOS || Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _offers = c.incomingOffers.listen(_showOffer);
    c.addListener(_scheduleAutoDismiss);
  }

  @override
  void dispose() {
    _offers?.cancel();
    c.removeListener(_scheduleAutoDismiss);
    super.dispose();
  }

  /// Successful transfers tidy themselves away; failures stay until dismissed.
  void _scheduleAutoDismiss() {
    for (final t in c.transfers) {
      if (t.status == TransferStatus.done && _autoDismissScheduled.add(t.id)) {
        Timer(const Duration(seconds: 8), () {
          if (mounted) c.dismissTransfer(t);
        });
      }
    }
  }

  Future<void> _showOffer(IncomingOffer offer) async {
    HapticFeedback.heavyImpact();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => IncomingSheet(offer: offer),
    );
    // Swiping the sheet away counts as "not now".
    offer.decline();
  }

  Future<List<PickedFile>> _pick({bool media = false}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: media ? FileType.media : FileType.any,
      );
      if (result == null) return const [];
      return [
        for (final f in result.files)
          if (f.path != null) PickedFile(f.path!, f.name, f.size),
      ];
    } on PlatformException {
      return const [];
    }
  }

  Future<void> _pickInto({bool media = false}) async {
    c.addPicked(await _pick(media: media));
  }

  Future<void> _tapDevice(Peer p) async {
    if (!c.isOnline(p)) {
      _toast('${p.info.name} is offline right now.');
      return;
    }
    if (c.activeTransferFor(p) != null) {
      _toast('Already sending to ${p.info.name}.');
      return;
    }
    if (c.picked.isEmpty) {
      await _pickInto();
      if (c.picked.isEmpty) return;
    }
    await c.send(p, askPin: () => askForPin(context, p.info.name));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _deviceMenu(Peer p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: DeviceAvatar(platform: p.info.platform, size: 36),
              title: Text(p.info.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(p.bestHost ?? ''),
            ),
            ListTile(
              leading: Icon(p.saved ? Icons.star_outline_rounded : Icons.star_rounded),
              title: Text(p.saved ? 'Remove from saved' : 'Save this device'),
              subtitle: p.saved ? null : const Text('Keep it here even when it\'s offline'),
              onTap: () {
                c.toggleSaved(p);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Forget'),
              onTap: () {
                c.forget(p);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addDevice() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AddDeviceSheet(controller: c),
      );

  void _settings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.88,
          child: SettingsSheet(controller: c),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final peers = c.peers;
            return Column(
              children: [
                SafeArea(bottom: false, child: _header(context)),
                if (c.startupError != null) _banner(context, c.startupError!),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: peers.isEmpty ? _emptyState(context) : _grid(context, peers),
                  ),
                ),
                TransferList(
                  transfers: c.transfers,
                  onDismiss: c.dismissTransfer,
                  onOpenFolder: c.openReceiveFolder,
                ),
                SendTray(
                  picked: c.picked,
                  totalBytes: c.pickedBytes,
                  showPhotos: _mobile,
                  onPickFiles: () => _pickInto(),
                  onPickPhotos: () => _pickInto(media: true),
                  onRemove: c.removePicked,
                  onClear: c.clearPicked,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 10, 6),
      child: Row(
        children: [
          const _Logo(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sushi Roll',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    'Visible as ${c.settings.deviceName}',
                    key: ValueKey(c.settings.deviceName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add device',
            onPressed: _addDevice,
            icon: const Icon(Icons.person_add_alt_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _settings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context, String text) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      );

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6);
    return Center(
      key: const ValueKey('empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radar(child: DeviceAvatar(platform: c.platform, size: 66)),
            const SizedBox(height: 8),
            Text('Looking around…',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Open Sushi Roll on another device. If it\'s on Tailscale or another network, add it by name once and it\'ll stay here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _addDevice,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add device'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, List<Peer> peers) {
    return LayoutBuilder(
      key: const ValueKey('grid'),
      builder: (context, box) {
        final columns = (box.maxWidth / 190).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 168,
          ),
          itemCount: peers.length + 1,
          itemBuilder: (context, i) {
            if (i == peers.length) {
              return EntranceAnimation(
                key: const ValueKey('add'),
                delay: Duration(milliseconds: 60 * i.clamp(0, 8)),
                child: AddDeviceTile(onTap: _addDevice),
              );
            }
            final p = peers[i];
            final active = c.activeTransferFor(p);
            return EntranceAnimation(
              key: ValueKey(p.info.id),
              delay: Duration(milliseconds: 60 * i.clamp(0, 8)),
              child: DeviceTile(
                name: p.info.name,
                platform: p.info.platform,
                subtitle: c.describeRoute(p),
                online: c.isOnline(p),
                saved: p.saved,
                inviting: c.picked.isNotEmpty,
                progress: active != null && active.status == TransferStatus.active ? active.progress : null,
                onTap: () => _tapDevice(p),
                onMore: () => _deviceMenu(p),
              ),
            );
          },
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: const LinearGradient(
          colors: [Palette.salmon, Palette.salmonDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Palette.salmon.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5)),
        ],
      ),
      child: CustomPaint(painter: _RollPainter()),
    );
  }
}

/// A tiny maki roll: nori ring, rice, salmon centre.
class _RollPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.32;
    canvas.drawCircle(c, r, Paint()..color = Palette.nori);
    canvas.drawCircle(c, r * 0.78, Paint()..color = Palette.rice);
    canvas.drawCircle(c, r * 0.38, Paint()..color = Palette.salmon);
  }

  @override
  bool shouldRepaint(_RollPainter oldDelegate) => false;
}
