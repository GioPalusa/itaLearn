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

Natural facial motion keeps the lids partly lowered between full blinks. Eyes
follow the source neck/head turns and make short, unevenly spaced glances;
upward gaze lifts the brows, while downward gaze lowers the lids. Small,
asymmetric smile and brow gestures ease in and out without opening the jaw.
Idle has a lifted mouth-corner baseline so the pauses retain a soft smile.
Eyes move first and the lids/brows settle behind them. The studio preserves
this behavior until manual face control is enabled; explicit shape overrides
and the closed-eye toggle still win. `--milo-demo --milo-idle-face-check` zooms
in and pauses only the body for a repeatable inspection of the natural face.
The 2026-09-12 face pass has 19 passing Milo tests and simulator captures in
`Art/Milo/Validation/2026-09-12-face`; physical-device appearance is unverified.

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

## Where Milo appears

`MiloMoments.swift` provides the placements. Milo normally appears directly in the
layout without a circular surround. The compact conversation identity and the
explicit round-avatar studio are the exceptions.

- `MiloPeek` trims space above the crown and lets the card cross his shoulders.
  Lesson overview uses a 220-point bust; flashcards use 144 points and progress
  uses a still 132-point portrait. The artwork takes no hits from the card.
- `MiloPracticeCanvas` measures exercise content independently of the mascot and
  uses only the remaining viewport, above the tab bar. It chooses a 260-point
  standing figure, a 152-point bust cropped to 121.6 points tall, or no figure.
  The figure follows the exercise's controller and never changes control positions.
  Accessibility text gets the whole viewport; Reduce Motion uses the smaller bust.
  Sentence building additionally opts into an extended body below the bottom safe
  area: a larger render viewport and inverse zoom preserve the head's size and
  position while revealing the torso behind the tab bar. This drawing is outside
  the scroll clip and cannot receive touches; the exercise still respects safe areas.
- `MiloGreetingCard` keeps a larger 188-point rig inside the greeting card, cropped
  to 140 by 156 points. There is no padding around the figure; the words have a
  small separate inset. Tapping the card cycles the study tip and plays a reaction.
- `MiloNarrationBar` supplies speech controls where the screen already has Milo.
  `MiloSpeechView` is the compact persistent chat row with a 44-point still mark,
  progress context, stop and retry controls. It remains visible while typing.
- `MiloLoadingView` uses a still portrait, so loading cannot create a second rig.
  Tiny repeated signatures were enlarged or removed where the name suffices.

Onboarding still greets in the chosen language and offers local speech when a
voice is available. Walking is restricted to full-body stages at least 230 points
wide. The game teacher reacts by the question card rather than from a tiny badge
in the scoreboard. Flashcards have a scroll fallback when the content is too tall.

Narration lifetime belongs to the screen: attach `.miloLifetime(controller)` to
its owner. `MiloAvatarView` and `MiloPeek` never call `controller.stop()` when their
layout disappears. This allows speech to continue when the keyboard opens or
when an optional visual no longer fits. The owner stops speech on navigation and
backgrounding. Rig size and zoom remain constant between layout choices.

See [the recovered design review](Milo-placement-review.md) for all twelve Claude
agents' results, the three unanimous votes, corrected technical assumptions and
implementation decisions. Latest device evidence is in
`Art/Milo/Validation/2026-09-12-placement/README.md`.

Validated on 2026-09-11: simulator Debug build and thirteen `MiloTests` passed.
Simulator captures verify circular framing, reactions returning to idle, and
local speech entering playback with a nonzero mouth meter before returning to
idle. Captures are under `Art/Milo/Validation/2026-09-11`. The eight existing
clips remain byte-for-byte unchanged. Physical-device rendering, acoustic audio
quality and touch interaction were not verified in this pass.

Validated on 2026-09-12: the iOS Simulator Debug build succeeded and all eighty
package tests passed. iPhone 18 Pro captures cover the three onboarding steps and
the peek crop over a lesson card, a flashcard stack and a sentence cue; the peek
captures came from a temporary host that is not in the tree. Touch interaction was
not exercised in this pass: the tap-to-hear greeting, the in-lesson reactions, the
practice ratings and the read-aloud controls were read from code, not driven. No
screen was checked on a physical device.
