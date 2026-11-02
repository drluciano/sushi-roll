# Phone preview

See UI changes on your iPhone a few minutes after they're pushed, without waiting for TestFlight. Nothing to install on the phone: it's a web page you open in Safari.

## The easy way: a link

Open **https://drluciano.github.io/sushi-roll/** in Safari on your iPhone (Share › Add to Home Screen makes it open full screen like an app).

Every push, to any branch, rebuilds it (`.github/workflows/preview.yml`, about 2 to 3 minutes), so it always shows the newest change. Reload the page to get the latest build. The Preview button shows which branch and commit you're looking at.

One-time setup: repo **Settings › Pages › Build and deployment**: Source **Deploy from a branch**, Branch **gh-pages**, folder **/ (root)**, Save. (The gh-pages branch appears after the workflow's first run.)

## The fast way: your PC

If you want changes in about a minute, with the page reloading by itself, run the preview server on your PC instead. Your PC builds the preview and serves it on your tailnet.

### One-time setup on the PC

1. Install **Git**: `winget install Git.Git`
2. Install the **Flutter SDK** (stable) in a folder **without spaces**, e.g. `git clone -b stable https://github.com/flutter/flutter.git C:\src\flutter`, and add `C:\src\flutter\bin` to PATH. If your Windows user name has a space (like `C:\Users\Dylan Rivera`), also set the user environment variable `PUB_CACHE=C:\src\pub-cache` and keep the repo under `C:\src`: Flutter's build hooks fail with "'C:\Users\Dylan' is not recognized" otherwise. Docs: follow https://docs.flutter.dev/get-started/install/windows (unzip it, add `flutter\bin` to PATH). Run `flutter doctor` once. You only need the "Chrome / web" part; Android Studio and Visual Studio aren't needed for the preview.
3. Clone the repo: `git clone https://github.com/drluciano/sushi-roll C:\src\sushi-roll` (Git will ask you to sign in to GitHub the first time).

### Running it

```
cd sushi-roll
dart run tool/preview_server.dart
```

It prints the addresses to open, e.g. `http://zephyrus:8090` (MagicDNS) or `http://100.x.y.z:8090`. Open that in Safari on your iPhone. The first build takes a minute or two; later ones are faster.

When Windows asks whether to let **dart.exe** through the firewall, tick both Private and Public and click **Allow** (Tailscale usually counts as a Public network).

Tip: in Safari, Share › **Add to Home Screen** opens the preview full screen, without Safari's toolbars, so it looks like the real app.

Leave the window open. By default it follows **whichever branch was pushed most recently**, so whatever Claude just pushed is what you see. To pin one branch: `dart run tool/preview_server.dart --branch main`. Other options: `--port 8090`, `--interval 10` (seconds between checks).

It builds in its own checkout under `.dart_tool/preview/`, so your clone's branch and files are never changed.

## The Preview button

A small **Preview** pill floats over the app (drag it anywhere). Tap it for:

- **Fold: No fold / Book / Passport.** Safari can't tell the app where iPhone Duo's fold is, so these add the same fold the app sees on the device: Book splits the screen side by side, Passport splits it top and bottom in the half-open posture. Unfolding the phone for real still changes the screen size as usual.
- **Incoming request**: shows the Accept/Decline sheet and a pretend incoming transfer.
- **Reset sample devices**.

The label at the top says which branch and commit you're looking at.

## What's the same as the app and what isn't

The same: every screen, sheet, animation and layout rule, light and dark mode, and iOS behaviour (Safari on an iPhone is treated as iOS, so you see the Photos button and iOS wording).

Different: nothing is really sent or received. Picking files gives sample files, sends are simulated, and typing an address with "fail" in it shows the error message. Text uses Flutter's bundled font rather than the iPhone's system font, so letters may look slightly different. iPhone Duo's camera strip isn't reported by Safari, so check anything near it on TestFlight.

Before a release, run TestFlight once to check on the real app (Actions › TestFlight › Run workflow).
