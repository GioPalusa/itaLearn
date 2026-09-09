# Milo / Snow export

The build reads the checksum-verified Snow and FBX files listed in
`Art/Milo/sources.json`. It writes the bundled USDZ, sampled clips, manifest,
fallback portraits and preview renders. The external source files and an
existing artist-owned `Milo_Master.blend` are never overwritten.

```sh
export MILO_ASSET_ROOT="/path/to/milo"
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python-exit-code 1 --python Scripts/milo/build_all.py -- "$PWD"
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python-exit-code 1 --python Scripts/milo/test_rig.py -- "$PWD"
swift test
```

## Arm rig invariants

- Exact Snow deform-bone names are mapped before facial heuristics. In
  particular, `Forearm` contains `ear` and must never map to the head.
- Overarms, twist segments, forearms and wrists retain separate skin weights.
  The four retained influences per vertex are renormalized.
- Edit-bone length is established before copying the source bind matrix.
  The exporter rejects a missing source bone or changed bind transform.
- Mocap rotation is transferred in world space as
  `sourcePose * inverse(sourceRest) * targetRest`, then converted to target
  parent-local rotation deltas. Copying source-local rotations directly is
  invalid because Snow and Mixamo use different local axes and bone roll.
- The clip file contains bind-relative deltas. RealityKit applies them after
  each joint's original local rotation; it retains bind translations/scales.

Regression tests inspect both the mapping and generated forearm surface,
and compare runtime bind heads/tails to the original Snow skeleton. Render
checks and the in-app character studio remain necessary to assess motion.
Launch with `--milo-demo`, or open the studio from Settings. Source/build
checks alone do not establish the device's rendered appearance.

## Idle motion and facial color

Six clips from `EVERYDAY-IDLES-MOCAP` are sampled at 30 fps while preserving
their source duration: Conversation, LookingAround, LookingAround02,
Chatting, Chatting02 and WatchingSomething. The last 0.4 seconds blend into
the opening pose for a continuous loop. Their source paths and checksums
are recorded in `Art/Milo/sources.json`.

Snow's skin and lip node graphs are baked without lighting into
`head_base.png`. Both baking and rendering explicitly use `UVMap`; the
source's alternate tattoo UV must not become the bake destination. The
exported head uses a direct image-to-base-color material supported by USDZ,
without relying on Blender shader groups or UDIM evaluation in the app.
