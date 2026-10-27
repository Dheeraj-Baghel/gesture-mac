# Gesture Mac - verification and handoff

## Animated gesture guide update

- Added **Watch gesture demo** to the main window, **Gesture demo** to both
  menus, and Command + D in the app. Six selectable vector animations demonstrate
  movement, click, held-pinch drag/drop, scroll, right-click and fist pause/resume.
- Play/Pause, Replay and wrapped Previous/Next controls work. Contact fingers
  are highlighted; step captions and a clearly labeled simulated result explain
  timing. The window supports its tested 760 x 640 minimum frame size.
- The guide has no camera, control-engine or input-controller references. Opening
  it disables real control and cancels calibration; enabling real control is
  refused while it is open. Closing it stops the timer and never resumes control.
- **31/31 unchanged core checks (98 assertions) pass again**, recorded in
  [core regression results](artifacts/testing/core-checks-demo.json).
- **18/18 native demo checks pass** in debug and release: selection/title/copy
  for all six tabs, actual timer clock advancement, playback, replay, navigation
  wrap, stable paused frame, and canvas/control visibility at default/minimum size.
  Separate assertions check opening/closing, input gating and animation cleanup.
  See [debug demo report](artifacts/testing/gesture-demo/native-demo-report.json)
  and [release demo report](artifacts/testing/gesture-demo/release-demo-report.json).
- The smoke tests capture three phases of each gesture (**18 snapshots**).
  Pixel differences in the hand-only regions confirm that all six illustrations
  change between sampled phases, not just their captions/progress indicators.
  Inspected all six mid-gesture drawings and the new main-window button.
  Examples: [click](artifacts/testing/gesture-demo/guide-click-2.png),
  [scroll](artifacts/testing/gesture-demo/guide-scroll-2.png),
  [pause](artifacts/testing/gesture-demo/guide-pause-2.png), and
  [main window](artifacts/testing/gesture-demo/main-with-demo.png).
- Debug/release compilation, bundle property-list validation and ad-hoc signature
  verification pass. The earlier optional Xcode search-path warnings remain.
- During these tests the **test instance's camera stays off and posts zero
  system input events**. An already-running user instance is not quit/restarted;
  the user should relaunch it to see the new button. No permission settings or
  other applications are changed.
- An early demo smoke run did not observe clock advancement. It was not counted
  as a pass; scheduled timer startup and the bounded observation interval were
  corrected. Final reports record actual timer callbacks and clock advancement.
- Reduce Motion starts the guide in a still pose; the current setting is
  respected in native checks, but changing system settings and physical
  VoiceOver/keyboard/mouse interaction remain manual. These are teaching diagrams,
  not live camera validation or a sustained animation-performance benchmark.

## Completed locally

- Native Swift/AppKit app builds in **debug and release** on Apple Silicon with
  Swift 6.4, the installed macOS SDK and Command Line Tools. No external Swift
  packages or global tools were installed. Deployment target is macOS 13;
  older macOS versions and Intel hardware were not tested.
- **31/31 deterministic checks, 98 assertions, zero failures**. See
  [core-checks.json](artifacts/testing/core-checks.json). Tests use synthetic
  2-D hand landmarks, not live camera images. They cover pose classification,
  confidence rejection, preview isolation, pinch debounce/hysteresis, cursor
  freeze, drag release, right-click debounce/disable, scroll entry/direction,
  fist hold/rearm, neutral startup hold, missing/multiple hands, stalled-frame
  watchdog, out-of-order frames, smoothing, mapping, settings and calibration.
- Built a proper locally **ad-hoc-signed** app bundle. Property-list validation
  and `codesign --verify --deep --strict` pass. This is not notarization or a
  distribution-ready Developer ID signature.
- Native app smoke checks pass in debug and release with **camera capture off
  and input hard-disabled**. See [debug report](artifacts/testing/native-smoke.json)
  and [release report](artifacts/testing/release-smoke.json).
  - Native window launches and renders; key controls/settings are within it.
  - One camera and one online built-in display are enumerated on this Mac.
  - All 21 Vision joints are mapped.
  - Control starts disabled; the UI's emergency-stop action disables it again.
  - Dry-run mode rejects move/down/up/right-click/scroll actions; **zero events
    are posted**.
  - The Carbon global stop hotkey registers successfully. Physical keypress
    delivery was not exercised by this test.
  - Screen-coordinate endpoint mapping matches the real display bounds.
  - Apple's actual Vision hand-pose request executes on an allocated **blank
    test image**, correctly returning zero hands. This verifies the local API
    path/model availability, not recognition accuracy. Timing varied widely:
    an earlier release sample was about 177 ms, while the final run recorded
    about 69 seconds. The display was asleep during these environment checks;
    the cause of the long outlier is not established. **Responsive real-time
    tracking is not verified and these are not FPS/latency benchmarks.** The
    live camera pipeline runs Vision off the UI thread; its watchdog pauses
    input if frames stall.
- Inspected the [native window capture](artifacts/testing/app-preview.png).
  It is explicitly a no-camera/no-input smoke-test screen, not a webcam demo.

## Issues found and addressed

- Full Xcode/XCTest is not installed. Replaced the initial XCTest test target
  with an explicit, dependency-free executable check runner. Failures produce
  a nonzero process exit; assertions are not disabled in optimized builds.
- Qualified the core joint type to avoid a collision with newer Vision APIs.
- Fixed an exclusive-access error in the synthetic pinch fixture and an
  ambiguous integer conversion in saved display preferences.
- An asleep display initially disappeared from the *active* display list.
  Enumerating *online* displays now preserves setup while asleep; input posting
  separately refuses asleep/offline displays. The native report now lists one
  display and confirms coordinate mapping. No display was woken by the app.
- Camera authorization/start requests use cancellation generations, preventing
  a late permission callback from restarting capture after Stop/close.
- Preview mirroring is reapplied after the capture connection exists. End-to-end
  mirror alignment still needs a real camera/hand check.
- Made the snapshot's background opaque and tightened spacing so the UI capture
  is readable and settings remain within the tested window.
- The CLT build emits missing optional Xcode-framework search-path warnings.
  These are disclosed; compilation, linking, signing and native execution pass.
  Some initial foreground tool build attempts timed out; completed background
  runs and the final reports are the evidence, not those failed attempts.

## Not verified - required before relying on control

**No camera permission was requested during automated verification, no live
webcam image was read, and no system mouse/scroll input was sent.** Permission
status queried from a test process can reflect its launching environment;
it is not proof that Finder-launched Gesture Mac already has access.

The user must launch the app, grant Camera and Accessibility access in macOS,
calibrate if necessary, then test in a harmless window:

1. Check the mirrored skeleton follows the correct hand and index tip.
2. Enable control and hold the one-finger pointing pose. Check all display
   corners are reachable without stretching or moving the hand out of frame.
3. Perform a single pinch click on a safe target, then a held pinch drag/drop.
4. Check two-finger vertical scroll and optional thumb/middle right-click.
5. Test fist pause/resume, hand disappearance and emergency-stop shortcut.
6. While dragging a harmless item, test hand loss, Stop, camera disconnect and
   normal Quit. Keep a physical mouse available.
7. Test display changes, sleep/wake, permission denial/revocation, different
   lighting, either hand, long sessions and an external camera/display.

Real-hand accuracy, end-to-end input delivery, camera/video latency, thermal
behavior, physical hotkey delivery, protected/secure UI, external hardware,
assistive-technology review and distribution/notarization are **not verified**.
The initial version does not implement typing, keyboard shortcuts, horizontal
scrolling, or a dedicated double-click gesture. Right-click context menus can
be used for Open actions. It is not a full mouse/keyboard replacement yet.

## Reproduce

From the [project folder](./):

```sh
mkdir -p artifacts/testing
GESTURE_MAC_CHECK_REPORT="$PWD/artifacts/testing/core-checks.json" swift run --disable-sandbox GestureCoreChecks
bash build-app.sh
GESTURE_MAC_SMOKE_REPORT="$PWD/artifacts/testing/release-smoke.json" "artifacts/macos/Gesture Mac.app/Contents/MacOS/GestureMac" --smoke-test --snapshot
```

Normal use must launch the app bundle, not its inner executable. Launching the
inner executable above is only for the explicitly input-disabled smoke test.
No deployment, login item, installation into Applications, persistent sleep
prevention, TCC database edits, permission bypass, recordings, network service,
paid API, unrelated application edit, or global dependency was added.
