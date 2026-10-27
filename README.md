# Gesture Mac

A standalone native macOS utility that turns **one webcam-tracked hand** into
pointer movement, left click, drag, right click, and vertical scroll. Built for
the user's request to use their Mac with hand gestures. This is a practical
pointer-control prototype, not a keyboard replacement or a medical device.

## Start

1. Double-click [Launch Gesture Mac.command](Launch%20Gesture%20Mac.command),
   or open the locally built Gesture Mac.app.
2. Click **Start camera** and allow macOS Camera access. A mirrored preview shows
   the hand landmarks and the movement range. No input is sent yet.
3. Click **Allow control access**. In **System Settings &gt; Privacy & Security &gt;
   Accessibility**, add/enable **Gesture Mac**. If not listed, use `+` and select
   the app bundle. Return to the app.
4. Choose the display to control. Optionally click **Calibrate movement range**:
   point at your comfortable upper-left reach, hold still, then repeat at your
   lower-right reach. Calibration never sends input.
5. Click **Enable control**. Hold a pointing pose briefly to arm the pointer.
   Test in a harmless window before using it for real work.

**Emergency stop: Control + Option + Command + G.** The menu-bar hand icon also
has **STOP Control**. Escape stops when the app window is focused. Closing the
window disables input and stops the camera; the menu-bar app remains available.

## Watch the gesture demo

Click **Watch gesture demo** at the top-right of the app. It is also available
from the app/menu-bar menus as **Gesture demo** (Command + D while this app is
focused). If the app is already running, quit and relaunch it to load the update.

The built-in guide has six animated, original hand illustrations: **Move,
Click, Drag, Scroll, Right click, and Pause/resume**. Gold highlights show which
fingertips touch. A simulated pointer/window alongside the hand shows the result,
and changing captions explain each step and hold time. Use **Play/Pause**, **Replay**,
**Previous**, **Next**, or select a gesture directly. With macOS Reduce Motion
enabled, the guide initially shows a still example; Play is an explicit opt-in.

**No camera or permissions are needed for the guide.** Opening it disables real
Mac control and cancels calibration. Real control cannot be enabled while the
guide is open, and closing it never resumes control automatically. Start the
camera and enable control yourself when ready. The drawings are illustrations,
not camera footage or proof of tracking accuracy.

See the [illustrated pinch example](artifacts/testing/gesture-demo/guide-click-2.png).

## Gestures

- **Move:** extend only the index finger; curl the other three fingers. Move the
  whole hand. The palm anchor drives the pointer so pinching disturbs it less.
- **Left click:** bring thumb and index fingertips together for at least 0.09 s,
  then separate them. The pointer freezes briefly to avoid clicking off target.
- **Drag:** keep the index pinch held for 0.38 s, then move the hand; open to drop.
- **Right click:** keep the index up, curl ring/little, and pinch thumb + middle.
  Hold for 0.15 s; release before repeating. This gesture can be disabled.
- **Scroll:** extend index + middle; curl ring/little. Move the hand up/down.
  The cursor stays in place. Natural scroll can be reversed in the app.
- **Pause / resume:** close all four fingers into a fist for 0.7 s. Release the
  fist before repeating. A deliberate pointing hold is required after resuming.
- **Rest:** open palm, drop the hand, or use Pause. No clicks are generated from
  an ambiguous pose. Extended tracking loss pauses until deliberately resumed.

Use one hand, a clear background, even front lighting, and a visible wrist and
fingertips. Either hand can be used; no handedness-specific coordinates. Keep a
mouse/trackpad available, rest often, and do not rely on it for safety-critical
operations. Recognition may fail with occlusion, rotation, poor light or depth.

## Privacy and safety

- Uses Apple's **Vision**, **AVFoundation**, **AppKit**, and **CoreGraphics** only.
  No Python, npm, external packages, accounts, API keys, uploads or recordings.
- Camera capture is explicitly started/stopped. Frames exist only in memory.
- Camera permission and Accessibility permission are separate and optional.
- Preview is the startup state every time; enabling control is never persisted.
- A low-confidence, missing or extra hand immediately ends a held drag on the
  next processed frame; a 0.75 s watchdog also pauses stalled tracking.
- Permission revocation, display changes, camera interruptions, sleep/lock,
  closing the window and quitting disable input and attempt to release buttons.
- One registered global stop shortcut is used, **not** a keyboard event tap.
  Input Monitoring and Screen Recording permissions are not required by the app.
- Calibration, smoothing, scroll direction, camera and display choices are saved
  in this app's local preferences. Camera images and hand landmarks are not saved.
- No access to login, security prompts, protected UI, or other users' sessions
  is promised. This cannot bypass macOS security.

## Build and checks

Requires macOS 13+ and Apple Command Line Tools (`xcode-select --install`) to
build. The current local app is built for this Mac's Apple Silicon architecture.
No full Xcode app is required. From this folder:

```sh
bash build-app.sh
swift run --disable-sandbox GestureCoreChecks
```

The package's deterministic checks use synthetic landmark fixtures and do not
request camera/Accessibility access or post system input. Full Xcode's XCTest is
not available in the current CLT-only installation; the checks therefore use an
explicit dependency-free executable runner, with a nonzero exit on failure.

[build-app.sh](build-app.sh) produces a proper `.app` bundle with a camera usage
message and an **ad-hoc** signature for local development. This is not a Developer
ID-signed/notarized distribution. Rebuilding or moving the app can invalidate
Accessibility authorization: remove/re-add it if access no longer works. Do not
run the bare Swift executable for normal use: permission attribution should be
to the app bundle. No login item, installer, global dependency, deployment, or
changes to other applications are added.

## Verification boundary

Debug/release builds, **31/31 deterministic checks (98 assertions)**, bundle
signing validation and safe native UI smoke checks pass. The actual Vision
request also executes on a generated blank test image. The camera remains off
and zero input events are posted during verification.
**Actual webcam recognition and system-wide control require the user's macOS
permission grants and physical-hand testing; they are not claimed verified by
synthetic tests.** See [VERIFICATION.md](VERIFICATION.md) for the completed results.

Typing, keyboard shortcuts, horizontal scrolling and a dedicated double-click
gesture are not implemented. This first version covers basic pointer control;
use a physical mouse/keyboard or context menus for the remaining actions.

## Source map

- [Package.swift](Package.swift): native app, pure gesture core, check runner.
- ControlEngine.swift: gesture state,
  debouncing, drag release, pause/resume and tracking-loss handling.
- Geometry.swift: pose math and mapping.
- Calibration.swift: two-corner calibration.
- CameraTracker.swift: serial camera/Vision
  processing, frame rejection and cancellation of old permission/start requests.
- InputController.swift: the only
  input-posting code; permission-gated and display-aware.
- AppDelegate.swift: native UI, menu bar,
  permissions, watchdog and system interruption handling.

## Apple references

- [Detect body and hand pose with Vision](https://developer.apple.com/videos/play/wwdc2020/10653/)
- [Camera authorization on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [VNDetectHumanHandPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest)
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)