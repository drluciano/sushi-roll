"""Applies Sushi Roll's platform settings to the folders `flutter create` made."""
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parent.parent

plist_path = root / "ios" / "Runner" / "Info.plist"
if plist_path.exists():
    with plist_path.open("rb") as f:
        plist = plistlib.load(f)
    plist.update({
        "CFBundleDisplayName": "Sushi Roll",
        "CFBundleName": "Sushi Roll",
        # Talking to devices on the same Wi-Fi.
        "NSLocalNetworkUsageDescription":
            "Sushi Roll finds and sends files to your devices on this network.",
        "NSPhotoLibraryUsageDescription":
            "Pick photos and videos to send to your other devices.",
        # The file picker library links camera and location APIs, so Apple
        # requires these strings even though Sushi Roll never asks for either.
        "NSCameraUsageDescription":
            "Take a photo or video to send to your other devices.",
        "NSLocationWhenInUseUsageDescription":
            "Sushi Roll doesn't use your location.",
        # Received files show up in Files > On My iPhone > Sushi Roll.
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
        # Plain HTTP to tailnet/LAN peers (traffic is encrypted by Tailscale).
        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True, "NSAllowsArbitraryLoads": True},
        # No custom crypto: skips the export-compliance question in TestFlight.
        "ITSAppUsesNonExemptEncryption": False,
        # Every orientation, so iPhone Duo's inner display can be held any way.
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UISupportedInterfaceOrientations~ipad": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
    })
    # Full-screen-only apps can't resize when iPhone Duo folds or unfolds.
    plist.pop("UIRequiresFullScreen", None)
    with plist_path.open("wb") as f:
        plistlib.dump(plist, f)

# duo_display (iPhone Duo fold reporting) needs iOS 15 or later.
IOS_MIN = "15.0"
pbxproj = root / "ios" / "Runner.xcodeproj" / "project.pbxproj"
if pbxproj.exists():
    src = pbxproj.read_text()
    src = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;", f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_MIN};", src)
    pbxproj.write_text(src)

podfile = root / "ios" / "Podfile"
if podfile.exists():
    src = podfile.read_text()
    src = re.sub(r"^#?\s*platform :ios, '[\d.]+'", f"platform :ios, '{IOS_MIN}'", src, flags=re.M)
    podfile.write_text(src)

framework_info = root / "ios" / "Flutter" / "AppFrameworkInfo.plist"
if framework_info.exists():
    with framework_info.open("rb") as f:
        info = plistlib.load(f)
    info["MinimumOSVersion"] = IOS_MIN
    with framework_info.open("wb") as f:
        plistlib.dump(info, f)

main_cpp = root / "windows" / "runner" / "main.cpp"
if main_cpp.exists():
    src = main_cpp.read_text()
    src = src.replace('L"sushi_roll"', 'L"Sushi Roll"')
    src = re.sub(r"Win32Window::Size size\(\d+, \d+\);", "Win32Window::Size size(1000, 720);", src)
    main_cpp.write_text(src)

rc = root / "windows" / "runner" / "Runner.rc"
if rc.exists():
    src = rc.read_text()
    src = re.sub(r'(VALUE "FileDescription", )"[^"]*"', r'\1"Sushi Roll"', src)
    src = re.sub(r'(VALUE "ProductName", )"[^"]*"', r'\1"Sushi Roll"', src)
    rc.write_text(src)
