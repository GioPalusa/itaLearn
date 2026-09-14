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
8.5–12: the left arm is retargeted relative to the chest, with the relaxed standing body
from Idle_LookAround. It plays once before returning to idle. Runtime clip
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
stage. Speech amplitude drives a smooth sequence across the open, wide, narrow,
rounded and lip/teeth shapes; AVSpeechSynthesizer does not expose phoneme timing.
Key/fill/rim lighting reveals both facial sides. Hand skin uses a three-tile
atlas instead of incorrectly sampling only the body texture tile.

`Laugh` and `Applaud` use the supplied ClassicTV Mixamo recordings, cropped to
seconds 3–7 and 3–8 respectively. Applause retains the recording's torso motion but solves both arm chains for
shared palm targets on Snow's proportions, producing six separated beats.
Palm contact lasts several frames. Runtime secondary smoothing is bypassed
for this clip so it cannot shorten the hand travel; transition blending remains. The runtime layers a smile and rhythmic mouth/eyelid movement
over laughter. Both clips play once; source hashes are pinned with the other recordings.

`Thinking` uses Mixamo's “Thinking While Standing” motion, downloaded without
skin at 30 fps. It is retargeted to Snow, looped with the same short tail blend
as the idle recordings and is used only for moments when Milo prepares or
evaluates something. Its exact source hash is pinned in `Art/Milo/sources.json`.

To rebuild clips and manifests using the existing generated rig, without
rebaking textures or touching the Blender master, append `--clips-only` after
the repository argument to `build_all.py`. This also renders the wave and reaction body
previews. A complete export calls the same clip builder.


## Expressive companion commands

`MiloController.perform` accepts `curious`, `enthusiastic`, `joyful`, `leanIn`,
`dance` and `present`, in addition to the existing actions. For example:

```json
{"action":"curious"}
```

The first four are authored combinations of Snow's eyebrow, cheek and mouth
morphs with small body/head movements. They rise and release over 4.5 seconds;
completion returns the controller to idle. `leanIn` combines torso movement with
a small approach/scale change, including in the orthographic circular portrait.
The avatar demo in Settings exposes all six actions. Reduced Motion retains a
still character. The studio defaults to automatic blinking; moving facial
sliders enables manual control, and Reset restores automatic control.

`Idle_Watching` now uses relaxed arms and wrists from `Idle_LookAround` across
the entire loop, rather than retaining the original held-hand pose. `Dance`
and `Present` use Quaternius CC0 `Dance_Loop` and `Interact`, respectively, from
the already downloaded, hash-verified Standard pack. They play once.

The home-page tip card now changes Milo's reaction when revealing a tip.
Suggested future placements: curiosity before revealing a clue; leaning closer
while inviting another attempt; joy after a successful correction; a brief dance
at a course milestone; and the presenting gesture beside the next exercise.
These are optional placements, not all automatically wired into lessons.

## Runtime surface materials and studio light

`prepare_surface_maps.py` prepares the original Blender Studio CC-BY maps from
`snow_barscene_pack`. Run with Blender and pass the pack directory after `--`.
Source hashes and modifications are recorded in `Art/Milo/surface-sources.json`.
The pack retains Snow's existing attribution in Settings. No source files are
modified. Head maps use UV tile 1001; body maps flatten tiles 1001–1003 to match
the existing body atlas. Colour maps use sRGB; roughness and normal maps stay
linear. Clothing receives the original normal maps. No invented skin normal map
is derived from freckles or colour, which would incorrectly emboss pigmentation.

`MiloAssets` applies these maps once to the cached USDZ template, keeping the
rig, morphs, eye culling and base colour textures intact. iOS 27 adds low-weight
subsurface scattering; older systems retain roughness/normal/specular changes.
Skin, hair, cloth and eyes have distinct specular responses. An authored broad
studio environment supplies soft light, with a stronger directional key, weaker
fill and subtle rim. The environment is shared across character instances.

These runtime overrides are intentional: Blender previews of the USDZ alone do
not show the final app material/light setup. Validate using the app's avatar demo.
