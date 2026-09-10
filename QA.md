# Verification notes

Verified on a MacBook Pro with M3 Pro, macOS 27, and Xcode 26.1.1.

## Completed

- Debug and Release builds succeeded.
- Eleven XCTest cases passed, including Metal readback and SwiftUI preview texture upload.
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

## Public release signing

- Signed with Developer ID Application for team RFKJ82VWM2, with hardened runtime and Apple's secure timestamp.
- Apple notarization accepted submission `cc60b26e-921a-4914-99aa-a182b49ddcb2`.
- Notarization ticket stapled to the app and validated.
- Strict signature checks passed for both Apple silicon and Intel architectures.
- Gatekeeper assessment returned `accepted`, with source `Notarized Developer ID`.
- Signing private keys and API credentials are excluded from source and release archives.

## Arc effect (1.0.3)

- Added a fourth selectable effect, Arc, to both the native preview and live renderer.
- The screen keeps its full height; its sides curve inward while the top and bottom remain pinned.
- The body softens progressively, using mip-filtered sampling to avoid sparse-tap artifacts.
- Native checks verified Arc selection, switching back to Silk, manual angle control, preview playback, and version 1.0.3.
- Two new Metal readback tests cover symmetric and resolution-independent curvature, increasing deformation, pinned edges, early diffusion, and exact restoration. All nine tests pass.
- Visually reviewed GPU frames and the four-item style row. Labels fit, selection is visible, and all existing controls remain accessible through the native scroll view.
- Live capture requested renewed Screen Recording permission during the 1.0.3 preview check; physical lid matching for Arc remains a user device check.
- 1.0.3 notarization accepted submission `1e51a8fb-f3c9-4508-aa2f-5351938c02d6`; the ticket was stapled and validated, and the installed app passed Gatekeeper as `Notarized Developer ID`.

## Book effect (1.0.4)

- Added Book as a fifth style, using the same Metal pipeline for preview and live capture.
- The left desktop leaf rotates around a vertical spine and covers the right leaf after crossing edge-on. The reverse face carries the mirrored left desktop content.
- Perspective fitting keeps the near edge within the display. Crease diffusion, foreshortening mip filtering, and a contact shadow preserve readable broad faces.
- Two new GPU tests verify exact clear and zero-perspective output, front-to-back overlap, continuity through ninety degrees, seamless spine contact, and consistent geometry at two resolutions. All eleven tests passed.
- Debug and universal Release builds succeeded. Native UI checks verified every style button, Book selection, manual preview, playback returning to the manual angle, and scrolling to the lower controls.
- Reviewed the five-style row, labels, selection indicator, spacing, contrast, and generated GPU frames. Existing styles retain their shader branches.
- Physical lid matching for Book remains a user device check.
- Apple accepted notarization submission `e43a80fa-7d8c-4810-ae12-6ff57fb8aebb`. The ticket was stapled and validated; Gatekeeper accepted the build as `Notarized Developer ID`.
