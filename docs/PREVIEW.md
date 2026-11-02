# Phone preview

See UI changes on your iPhone a minute after they're pushed, without waiting for TestFlight and without using GitHub Actions minutes.

Your Windows PC watches GitHub. When a branch gets a new commit, it builds the app's UI for the web (with sample devices and pretend transfers, no real networking) and serves it on your tailnet. Safari on your iPhone shows it, and the open page reloads by itself when the next build is ready.

## One-time setup on the PC

1. Install **Git**: `winget install Git.Git`
2. Install the **Flutter SDK** (stable): follow https://docs.flutter.dev/get-started/install/windows (unzip it, add `flutter\bin` to PATH). Run `flutter doctor` once. You only need the "Chrome / web" part; Android Studio and Visual Studio aren't needed for the preview.
3. Clone the repo somewhere: `git clone https://github.com/drluciano/sushi-roll` (Git will ask you to sign in to GitHub the first time).

## Running it

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
