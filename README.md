# Sushi Roll

Send files between your devices with one tap: iPhone, iPad and Windows, on the same Wi-Fi **or across Tailscale**.

Most local file senders discover each other only with multicast or broadcast. That fails on guest/office networks that isolate clients, and Tailscale doesn't carry multicast at all. Sushi Roll uses discovery only to find an address. Everything else is plain HTTP to that address, so it works wherever two devices can reach each other.

## How devices find each other

1. **Same Wi-Fi:** UDP multicast announcements, when the network allows them.
2. **Tailscale (Windows/macOS/Linux):** the app reads `tailscale status --json` and checks each online peer.
3. **Add by name:** type a MagicDNS name (`my-pc`) or a tailnet IP (`100.x.y.z`) once, and it's saved.
4. **Word of mouth:** every device says hello to those it finds and shares its peer list. iOS can't read the Tailscale peer list, so your PC introduces your iPhone to everything else.

## Using it

- Pick files (or photos) at the bottom, then tap a device.
- Tapping a device with nothing picked opens the picker first.
- The receiver gets an Accept/Decline sheet. You can also require a 4-digit PIN in Settings.
- Received files go to `Downloads\Sushi Roll` on Windows (you can change this), and to **Files › On My iPhone › Sushi Roll** on iOS.
- Long-press a device to save or forget it.

## Development

Requires the Flutter SDK (stable).

```bash
./tool/bootstrap.sh     # generates ios/ and windows/ and applies our settings
flutter run -d windows  # or an iOS device
flutter test
```

The native platform folders aren't committed yet. CI generates them with `tool/bootstrap.sh`, so the repo can be built entirely from GitHub Actions.

- **CI** (`.github/workflows/ci.yml`): analyze, test, Windows build (download the artifact), and an unsigned iOS build.
- **TestFlight** (`.github/workflows/testflight.yml`): every push to `main` is signed and uploaded. See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the protocol.
