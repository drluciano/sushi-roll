import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/discovery/tailscale.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets/ambient.dart';
import 'widgets/device_tile.dart';

// ------------------------------------------------------------------ incoming

class IncomingSheet extends StatefulWidget {
  const IncomingSheet({super.key, required this.offer});

  final IncomingOffer offer;

  @override
  State<IncomingSheet> createState() => _IncomingSheetState();
}

class _IncomingSheetState extends State<IncomingSheet> {
  IncomingOffer get offer => widget.offer;

  @override
  void initState() {
    super.initState();
    // Close when answered: by a button here, or by the request timing out.
    offer.answered.then((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = offer.session;
    final count = s.files.length;
    final shown = s.files.take(4).toList();
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radar(size: 150, child: DeviceAvatar(platform: s.sender.platform, size: 64)),
            Text(s.sender.name,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'wants to send you ${count == 1 ? 'a file' : '$count files'} · ${formatBytes(s.totalBytes)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 18),
            for (final f in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(fileIcon(f.name), size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(formatBytes(f.size), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
            if (count > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('and ${count - shown.length} more',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: offer.decline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      offer.accept();
                    },
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ add device

class AddDeviceSheet extends StatefulWidget {
  const AddDeviceSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<AddDeviceSheet> createState() => _AddDeviceSheetState();
}

class _AddDeviceSheetState extends State<AddDeviceSheet> with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _busy = false;
  bool _ok = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy || _text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.addByAddress(_text.text);
    if (!mounted) return;
    if (error != null) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _ok = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add a device',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Type its Tailscale name or IP address. You can find it in that device\'s Sushi Roll settings.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 18),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = (1 - t) * 10 * math.sin(t * 6 * math.pi);
                  return Transform.translate(offset: Offset(dx, 0), child: child);
                },
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(
                    hintText: 'my-pc  or  100.101.42.7',
                    prefixIcon: Icon(Icons.dns_rounded),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_error!,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy || _ok ? null : _connect,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _ok
                        ? const Icon(Icons.check_rounded, key: ValueKey('ok'))
                        : _busy
                            ? const SizedBox.square(
                                key: ValueKey('busy'),
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text('Connect', key: ValueKey('idle')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ pin

Future<String?> askForPin(BuildContext context, String deviceName, {Offset? anchorPoint}) {
  final text = TextEditingController();
  return showDialog<String>(
    context: context,
    anchorPoint: anchorPoint,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: const Text('Enter PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$deviceName asks for a PIN. It\'s shown in Settings on that device.'),
          const SizedBox(height: 16),
          TextField(
            controller: text,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (v) => Navigator.of(context).pop(v),
            decoration: const InputDecoration(counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.of(context).pop(text.text),
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ settings

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final _name = TextEditingController(text: widget.controller.settings.deviceName);
  String? _receivePath;

  bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    widget.controller.receiveDirectory().then((d) {
      if (mounted) setState(() => _receivePath = d.path);
    });
  }

  @override
  void dispose() {
    widget.controller.rename(_name.text);
    _name.dispose();
    super.dispose();
  }

  void _copy(String s) {
    Clipboard.setData(ClipboardData(text: s));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $s')));
  }

  Future<void> _chooseFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Save received files to');
    if (path == null) return;
    widget.controller.setReceiveDir(path);
    setState(() => _receivePath = path);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6);
    final ts = c.myTailscaleAddresses;
    final others = c.myAddresses.where((a) => !Tailscale.isTailscaleAddress(a)).toList();

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, color: muted)),
        );

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text('Settings', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            section('This device'),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.done,
              onSubmitted: c.rename,
              decoration: InputDecoration(
                prefixIcon: Icon(platformIcon(c.platform)),
                hintText: 'Device name',
              ),
            ),
            section('Your address'),
            if (ts.isEmpty)
              Text(
                'Tailscale isn\'t connected on this device. Devices on the same Wi-Fi can still find you.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            for (final a in ts) _AddressPill(address: a, label: 'Tailscale', onCopy: () => _copy(a)),
            if (others.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Other addresses', style: theme.textTheme.bodyMedium),
                  children: [
                    for (final a in others) _AddressPill(address: a, onCopy: () => _copy(a)),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              _desktop && c.tailscaleCliAvailable
                  ? 'Tailscale found. Your other devices running Sushi Roll will show up automatically.'
                  : 'On another device, tap "Add device" and type one of these. After that, they\'ll find each other automatically.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            section('Privacy'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require a PIN'),
              subtitle: const Text('Senders type it before you see their request'),
              value: c.settings.pinEnabled,
              onChanged: c.setPinEnabled,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: !c.settings.pinEnabled
                  ? const SizedBox(width: double.infinity)
                  : Row(
                      children: [
                        Text(c.settings.pin,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 10,
                              color: theme.colorScheme.primary,
                            )),
                        const Spacer(),
                        IconButton(
                          tooltip: 'New PIN',
                          onPressed: c.regeneratePin,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
            ),
            if (_desktop) ...[
              section('Received files'),
              Row(
                children: [
                  const Icon(Icons.folder_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_receivePath ?? '…',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  ),
                  TextButton(onPressed: _chooseFolder, child: const Text('Change')),
                ],
              ),
            ] else ...[
              section('Received files'),
              Text('Open the Files app → On My iPhone (or iPad) → Sushi Roll.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ],
            const SizedBox(height: 28),
            Center(child: Text('Sushi Roll 0.1', style: theme.textTheme.bodySmall?.copyWith(color: muted))),
          ],
        ),
      ),
    );
  }
}

class _AddressPill extends StatelessWidget {
  const _AddressPill({required this.address, required this.onCopy, this.label});

  final String address;
  final String? label;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: label != null ? 0.1 : 0.04),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onCopy,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(address,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(label!, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                  ),
                const Icon(Icons.copy_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
