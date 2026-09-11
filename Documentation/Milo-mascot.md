# Milo, LangLearn's teacher

Milo uses Snow v4.2 from Blender Studio (CC-BY-4.0), retaining the supplied
face, hair, clothing and proportions. Settings contains credits and the local
character studio. Rendering uses bundled assets without a network request.
Generated portraits match the model and serve as compact and Reduce Motion
fallbacks. Existing learner data and model configuration are preserved.

## Animation and studio

RealityKit loads the model once, clones it for each visible teacher, and applies
sampled skeletal motion plus fifteen independent facial morphs. Six original
idle recordings are joined by a standing wave, an in-place walk, laughter and
applause. Greetings
wave once and settle into idle; the home character can take a short bounded
walk. Transitions blend from the current pose. Inactive scenes stop animation.

The mouth deformation includes lips, jaw, teeth, gums and tongue. Speech
amplitude drives opening; it is not phoneme-aligned lip sync. Blinking and gaze
are independent. Both eyes rotate in head space, compensating for their
opposite bind rolls. A portable iris/pupil material preserves color, and explicit double-sided
rendering prevents RealityKit from culling the recessed pupil surface. The exporter evaluates Snow's actual rig and animation slot
instead of exporting shapes whose names exist but whose geometry stays neutral.
Key, fill and rim lights illuminate both sides of the face. Hands use all three
skin texture tiles instead of sampling the body tile for every UV region.

The studio keeps its preview visible above scrolling controls. It exposes face
zoom, body pause, clip replay, stage walking, mouth opening, gaze, independent
face shapes and reset. It is accessible from Settings or a Debug launch with
`--milo-demo` and uses only local system speech.

## Sources and validation

See `Scripts/milo/README.md` for reproducible export commands and rig invariants.
Paths and hashes are pinned in `Art/Milo/sources.json`. The artist-owned master
and original files are preserved. Generated exports are copied to app resources.

The walk comes from the free Standard edition of
[Quaternius Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html),
licensed CC0. Downloaded files, license and provenance are under
`Art/Milo/Source/Quaternius`. The wave and idles use the supplied local mocap.

Run `swift test --filter MiloTests` and `Scripts/milo/test_rig.py` in Blender.
They check real asset loading, facial displacement, independent controls, reset,
clip transitions and bounded walking. Compare before/after geometry in the
studio as well: a successful build and named blend shapes alone do not prove
visible animation.

Debug render fixtures `--milo-demo --milo-face-check` and
`--milo-demo --milo-motion-check` change the same live state as the studio
controls after launch. The face sequence covers neutral, open mouth, closed
lids, both gaze directions on each axis, and reset. It labels the active pose.
These support repeatable simulator captures without modifying learner data.

Validated on 2026-09-10: the iOS Simulator Debug build succeeded, all ten
`MiloTests` and five Blender rig tests passed, and exported assets matched the
copies in the built app. iPhone 18 Pro simulator captures verified face zoom,
mouth opening, eyelid closure, gaze, reset, waving, walking, turning and the
return to idle. The render fixtures exercise the controls' state bindings;
physical-device rendering, touch/drag interaction and live speech playback
were not verified in this pass.
Selected simulator captures and a motion recording are saved under
`Art/Milo/Validation/2026-09-10`.

## Circular avatar and commands

`MiloAvatarView` renders a circular face portrait at any size, including a live
32-point avatar. It uses the same cached rig, virtual camera and speech meter.
Use one live avatar beside the active conversation; use `mood: .still` for
historical messages. Reduce Motion, inactive scenes and loading use the matching
portrait. No camera permission or network call is needed.

Keep one controller in the owning view's state:

```swift
@State private var milo = MiloController()

// Inside body:
MiloAvatarView(controller: milo, size: 96)

// In event handlers, separately:
milo.laugh()
milo.applaud()
milo.wave()
milo.speak("Bravissimo! Proviamo ancora?", in: .italian)
milo.stop()
```

`think()`, `listen()`, `encourage()` and `idle()` set ongoing states. Laughter,
applause and waving play once and return to idle. Repeating a call replays it;
a new command replaces the previous action or speech. Completion comes from
the animation timeline, so a cold model load cannot consume the reaction.
Disappearance/backgrounding stops speech and animation. Laughter and applause
are visual reactions without sound effects; `speak` uses the local system voice
and drives the mouth from the actual audio amplitude.

Callers may also supply decoded function-call arguments:

```swift
try milo.perform(MiloCommand(action: .applaud))
try milo.perform(json: Data(#"{"action":"speak","text":"Ciao!","language":"it"}"#.utf8))
```

Allowed actions are `idle`, `laugh`, `applaud`, `wave`, `think`, `listen`,
`encourage`, `speak` and `stop`. Speech requires nonblank text and a language code
from `LearningLanguage.catalog`. Invalid input leaves the current action intact.
This is a local dispatch API; registering an OpenAI tool or choosing when a model
should call it is the caller's responsibility.

The chat speaker and message portraits use this component. Lesson summaries
applaud a completed lesson. Settings → Milos studio → Prova den runda avataren
opens the interactive demo. Debug launches can use `--milo-avatar-demo` and
`--milo-avatar-check` for a repeatable sequence through the same controller API.

Validated on 2026-09-11: simulator Debug build and thirteen `MiloTests` passed.
Simulator captures verify circular framing, reactions returning to idle, and
local speech entering playback with a nonzero mouth meter before returning to
idle. Captures are under `Art/Milo/Validation/2026-09-11`. The eight existing
clips remain byte-for-byte unchanged. Physical-device rendering, acoustic audio
quality and touch interaction were not verified in this pass.
