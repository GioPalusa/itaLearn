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
their source timing: Conversation, LookingAround, LookingAround02,
Chatting, Chatting02 and WatchingSomething. The last 0.4 seconds blend into
the opening pose for a continuous loop. Two calibration samples (T-pose and
its transition) are removed before the loop is built. Their source paths and checksums
are recorded in `Art/Milo/sources.json`.

Snow's skin and lip node graphs are baked without lighting into
`head_base.png`. Both baking and rendering explicitly use `UVMap`; the
source's alternate tattoo UV must not become the bake destination. The
exported head uses a direct image-to-base-color material supported by USDZ,
without relying on Blender shader groups or UDIM evaluation in the app.

## Walking, waving and facial motion

`Walk` is the free CC0 `Walk_Loop` from Quaternius' Universal Animation Library
Standard. Downloaded glTF, binary, license and provenance are under
`Art/Milo/Source/Quaternius`; hashes are checked before export. Native loop timing
is preserved. `Wave` uses the supplied Rokoko Pilot Wave recording, seconds
8.5–12: the left arm is retargeted relative to the chest, with the standing body
from WatchingSomething. It plays once before returning to idle. Runtime clip
transitions blend from the currently displayed pose.

`face_export.py` evaluates Snow's actual rig, including its action slot, at the
expression's final frame. Fifteen neutral-relative morphs share a mesh with the
head, eyebrows, teeth, gums and tongue. The old export could list blink shapes
without any eyelid motion. `mouthOpen` bakes jaw and lip deformation together;
the runtime must not also rotate the jaw. Gaze uses independent eye joints with deltas in common head space: Snow's
eye bind rolls differ. Eyes use a direct iris texture material for USDZ. Runtime materials explicitly
preserve double-sided rendering so the recessed pupil does not disappear.
Regression tests require substantial eyelid motion on the correct side and
moving teeth, rather than checking shape names alone.

The studio keeps its preview visible while scrolling controls, with face zoom,
body pause, direct mouth opening, eyelids, gaze, replay and walking across the
stage. Speech amplitude drives mouth opening, not phoneme-accurate lip sync.
Key/fill/rim lighting reveals both facial sides. Hand skin uses a three-tile
atlas instead of incorrectly sampling only the body texture tile.

`Laugh` and `Applaud` use the supplied ClassicTV Mixamo recordings, cropped to
seconds 3–7 and 3–8 respectively. They retain Snow's bind-relative retargeting.
The runtime layers a smile and rhythmic mouth/eyelid movement over laughter.
Both clips play once; source hashes are pinned with the other recordings.

To rebuild clips and manifests using the existing generated rig, without
rebaking textures or touching the Blender master, append `--clips-only` after
the repository argument to `build_all.py`. This also renders the two new body
previews. A complete export calls the same clip builder.
