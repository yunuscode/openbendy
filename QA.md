# Verification notes

Verified on a MacBook Pro with M3 Pro, macOS 27, and Xcode 26.1.1.

## Completed

- Debug and Release builds succeeded.
- Seven XCTest cases passed, including Metal readback and SwiftUI preview texture upload.
- Native settings controls were exercised: styles, preview playback, effect sliders,
  Follow lid, navigation, sound toggle, reset, and permission recovery.
- ScreenCaptureKit started after Screen Recording permission was granted.
- Physical lid movement changed the effect continuously, with approximately 60 Metal
  draw submissions per second and sensor reads every 33 ms.
- The overlay hid above the clearing angle and appeared below it.
- Escape paused the effect with OpenBendy focused; relaunch resumed capture.
- The live fold was tested with physical lid movement and accepted by the tester.
- Generated Metal frames were inspected for edge softness, early blur, and hinge detail.
- The native preview, icon, About branding, alignment, and text contrast were inspected.
- `docs/settings.jpg` is an actual capture of the OpenBendy settings window.

## Remaining device checks

- Clear sound during a physical opening cycle.
- Global Esc while a different app has focus.
- Open-at-login registration.

Hardware compatibility beyond the tested MacBook has not been verified.
