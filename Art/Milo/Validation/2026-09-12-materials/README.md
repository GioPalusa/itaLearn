# Milo surface and light validation — 2026-09-12

- Debug simulator build succeeded with Xcode, iPhone 18 Pro / iOS 27.
- All 15 Milo animation/lifecycle/rig tests passed; these do not measure material appearance.
- `before.png` and `after.png` are app screenshots from the circular avatar demo.
  The camera/size is unchanged; idle animation means head poses differ.
- Visually inspected skin, eyes, hair and shirt in the simulator. The final
  material has reduced broad skin highlights and visible cloth normal detail.
- Original Snow roughness maps, clothing normals and skin scattering maps load
  from the bundle. Subsurface scattering is gated to iOS 27; the older-system
  fallback has been compiled but not rendered on an older simulator.
- Soft studio environment plus directional key/fill/rim is configured in app,
  so a Blender-only preview is not a rendering parity test.
- No physical iPhone visual or performance validation was performed.
