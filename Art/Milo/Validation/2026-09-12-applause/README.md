# Applause contact repair — 2026-09-12

The old source-pose interpolation left the hands at different heights and depths.
The exporter now solves both wrist targets using Snow's arm lengths, and aligns
opposing palm normals. Six claps have a 90 ms contact hold and separated release.
The torso retains its source movement. The app bypasses its second body low-pass
filter during Applaud; the animator still handles clip entry and exit blending.

Validation:
- 16 Milo tests passed, including FK on the actual bundled USDZ skeleton with
  the actual clip binary: six separated contacts, opposing normals and release.
- Palm markers are defined in hand-local space, 6 cm along the hand and 1.2 cm
  toward the palm surface. This is a contact constraint, not a mesh collision test.
- Export report: 17 held-contact samples, maximum marker gap 4.16 mm.
- Simulator Debug build passed.
- Blender contact/release renders inspected; simulator recording and frame
  captures accompany this note. Physical device playback remains unverified.

`contacts.png` contains 24 consecutive simulator-video samples at 80 ms intervals
(starting at video time 5.0 s). Visually checked repeated palm contact followed
by separation. Recording device: iPhone 18 Pro, A764AF99-8DC1-43E1-A258-F9AC5EBFC30F.
