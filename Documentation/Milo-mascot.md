# Milo, LangLearn's teacher

Milo is an original lavender fox with large plum eyes, a cream muzzle and a golden scarf. The learner meets Milo in setup, the study plan, lesson introductions, assistant messages, loading states and lesson summaries. Tapping Milo on the study plan cycles through four local study tips. Teaching and assessment prompts share the same identity; underlying model IDs and assessment rules are unchanged. Settings still disclose the OpenAI provider, API billing and data handling.

## Assets and animation

Created with the built-in image-generation tool, not the API/CLI fallback. Both PNGs retain transparent alpha and are bundled in the app; displaying and animating Milo makes no network request.

- `LangLearn/Assets.xcassets/Milo.imageset/milo.png`: welcoming pose, 1254 × 1254.
- `LangLearn/Assets.xcassets/MiloThinking.imageset/milo-thinking.png`: matching thoughtful pose with notebook.
- `LangLearn/MiloView.swift`: static avatar, gentle greeting sway, thinking bob, celebratory hop, and a bounded 12-point sideways wander on the home greeting. These are whole-character SwiftUI transforms, not frame-by-frame limb animation.
- `LangLearn/TeacherIdentity.swift`: shared model-facing persona.

Animations render only while the view is mounted and the scene is active. System Reduce Motion selects the static artwork. Repeated chat avatars stay still. The home mascot button has a VoiceOver label and hint; decorative images are hidden from accessibility. The greeting stacks vertically at accessibility text sizes and otherwise reserves a fixed mascot area beside wrapping text. It never floats over lesson controls.

Existing saved conversations and plans are preserved. Their original wording is not rewritten; newly generated answers use Milo's identity.

## Final generation prompts

Welcoming pose:

> Create one original polished mobile app mascot asset for LangLearn: Milo, a cute friendly baby lavender fox Italian language teacher. Single full-body character, enormous expressive deep plum eyes with crisp white catchlights, rounded triangular ears, soft cream muzzle and belly, little dark plum nose, friendly modest open smile, short rounded paws, fluffy curled tail with cream tip, warm golden yellow small scarf. Lavender fur #8070B8 and darker purple accents #564797, very subtle rosy cheeks. One forepaw raised in a welcoming wave, standing facing viewer in gentle three-quarter view. Premium 2D cartoon illustration, clean confident rounded outlines, smooth flat colors with restrained soft shading, charming and approachable for adults as well as children, legible at 64 px. Distinct original fox silhouette, not an owl, not resembling existing app mascots. Entire body, both ears and tail fully visible, centered within square with 10 percent clear padding. Isolated on a genuine transparent alpha background. No text, no letters, no logo, no scene, no background shapes, no cast floor shadow. Deliver a single production-ready transparent PNG mascot asset.

Thinking pose (welcoming PNG used as the identity reference):

> Create a second matching animation-state asset of this EXACT same original character Milo. Preserve identical lavender fox identity, huge deep plum eyes, cream muzzle/belly and tail tip, golden yellow scarf, proportions and rendering style. Change ONLY the pose/expression to thoughtful and helpful: mouth in a small gentle closed smile, one little forepaw resting by the chin, the other holding a small closed cream notebook with no markings. Eyes looking slightly upward as if preparing a helpful explanation. Full body, entire ears feet and tail visible; same front three-quarter view and same square canvas, character fits with clear padding. Genuine transparent alpha background, no background or text or lettering, isolated production PNG for a mobile app. This is a friendly thinking pose, not worried or sad.

## Validation

The Xcode build and the 30 existing core tests passed. iPhone 17 Pro previews were rendered and inspected for the home page, loading poses, onboarding and accessibility text sizes. Source review covers the Reduce Motion, active-scene and view-lifecycle gates. Physical-device animation, VoiceOver interaction and a live model response with the new persona still need hands-on verification.
