# Adaptive language learning

LangLearn uses a user-provided OpenAI API key, GPT-5.6 Sol for placement and planning, and GPT-5.6 Luna for teaching. The learner picks both languages during onboarding: the target language they are learning and the language Milo explains, corrects and summarizes in. `LearningLanguage.catalog` holds the offered pair of languages, each with a speech/dictation locale, an English name used in model instructions and any usage habit worth handing the tutor. `LanguageCourse` carries the chosen pairing into every request, both as prompt text and as JSON data. The app's own UI strings remain Swedish. The existing Apple-model dependency and Private Cloud Compute entitlement have been removed.

## Guided journeys (September 14)

The default navigation is **Idag**, **Upptäck**, **Min resa**. Each target language has its own explicit starting profile: self-reported experience (new, simple phrases, everyday conversation, or free expression), familiarity with the script, practical goal, interests and session length. A new profile requires an explicit experience choice; it does not silently default an experienced learner to beginner. Placement is optional. Profile choices are editable and separate from observed answers.

Two tracks share one resumable lesson engine:

- **Ljud och tecken** starts with demonstration, meaning, listening and script matching, plus voluntary speech imitation. It never requires typing. Language-specific inventories constrain script choices; kana, Hangul blocks and Chinese characters are not described as Latin-style alphabets. Audio demonstrates whole words. These are introductory inventories, not a complete reviewed orthography curriculum or stroke-order course.
- **Vardagsuppdrag** uses the learner's goal, interests, selected situation and recent evidence. New learners answer with choices. Learners comfortable with the script can encounter supported writing after three independently recognized skills, or when they explicitly report some prior experience. This changes activities, not an asserted proficiency level. Examples and hints remain available.

Experienced users start with a complete situation, follow-up questions or open responses; their mission must contain a sentence-level writing or listening task. A prior assessment for the same target language is included as an informal written estimate, never proof of speaking ability. Experienced speakers learning a new script retain meaningful spoken situations alongside script recognition. Completing a lesson offers **För lätt**, **Lagom**, **För svårt**; the last three choices are included in generation context to change the next challenge while preserving reading constraints.

A network-free greeting is bundled for every target with Swedish or English explanations. Other explanation languages, and subsequent personalized lessons, require the existing user API key. The key can be added after selecting a starting profile. The offline greeting is offered only for a completely new learner, not as the default for someone experienced.

`JourneyRequest` includes at most 20 recent observations and four due review items. A single Luna request prepares 3–8 steps with hints, examples and local answer keys (`guided_journey_v1`, strict schema, 8,000 output tokens maximum). Choice answers and word tiles are checked locally. Only free writing makes an additional request (`guided_answer_v1`, 1,500 output tokens maximum). Invalid JSON, wrong language codes, invalid choices, impossible tile answers, unsuitable typing requirements and out-of-inventory script choices are rejected before display. Schema conformance does not prove linguistic or pedagogical accuracy.

Sessions persist their cursor, draft, tiles, hints, playback evidence and pending writing attempt. Pending answers have stable attempt IDs; duplicate/stale results cannot award evidence twice. Leaving a screen cancels its request. Failed requests need an explicit retry; there is no automatic paid retry loop.

Recognition, writing and self-reported speech remain distinct. Hearing a reading prompt or revealing a listening transcript marks support; transcript-assisted listening becomes reading evidence. A speaking attempt is self-reported, with no microphone or pronunciation score. Reviews use 1/3/7/14-day intervals, counting successful days rather than repeated same-day taps. Explicit profile preferences about unfamiliar script remain in force after a greeting is completed.

Milo is owned by the active screen: a responsive portrait on Today, a full figure introducing a session, a portrait attached to the current teaching card, and a full-figure completion celebration. Taps trigger curiosity, laughter, a greeting or a celebration. Guidance and answer reactions use actual session events. Profile/library decoration uses the existing matching still portraits. Reduce Motion uses the existing still-image fallback. Feedback and hints scroll into view, and advancing restores the top of the next step.

For reproducible simulator checks, launch `--journey-preview` with optional `--journey-lesson`, `--journey-script`, `--journey-complete`, `--journey-large-text` or `--journey-setup`. These DEBUG fixtures use an isolated in-memory store and do not read credentials. Generated-pack quality and real OpenAI account/model access require separate live validation.

## Optional assessment and existing curriculum

1. For generated lessons and assessment, the learner supplies their own API key. Settings supports replacing or removing it. Keys are stored with Keychain Services, `WhenUnlockedThisDeviceOnly`, with synchronisation disabled. No key is bundled, saved in preferences, or written to learning records. Key entry checks format; the first model request verifies actual API access.
2. Choosing the optional knowledge check under Upptäck opens a six-question written placement chat. After each of the first five answers Sol generates one adaptive follow-up. The learner can say they do not know. After answer six, Sol returns a strict JSON assessment; there is no seventh question.
3. The app validates the version, languages, estimated level, lesson counts, IDs, prerequisites and required content before saving anything. It retains the original response JSON and renders the returned lessons as the study plan. This is an informal estimate of written ability, not a certified CEFR assessment or an assessment of pronunciation.
4. Luna receives the learner profile, the selected lesson, achieved objective indices, a compact pedagogical summary and at most 16 recent messages. It corrects errors, explains them in the learner's chosen explanation language, and asks for another attempt when needed. Each reply replaces the compact learning summary so important errors and the current task survive context trimming.
5. The app refuses replies that simultaneously request a retry and award objectives or finish a lesson. Opening turns cannot award progress. A separate wrap-up assessment determines mastery from demonstrated objectives and success criteria, after at least two learner answers and with no unresolved retry. Prerequisites determine which lessons are available.
6. Reassessment uses the six new answers, the current plan/progress and up to six recent lesson summaries. `continueCurrent` updates the profile while preserving plan identity, lesson progress and conversations. `newPlan` archives the old plan and starts the returned plan. Every assessment and previous conversation remains available in Mitt lärande.

## Lesson endings and practice (September 9)

A session wraps up when all objective indices have been credited, after eight learner answers (including retries), when the teacher signals completion, or when the learner chooses **Avsluta och sammanfatta** after two answers. Long conversations saved by the previous version also reach wrap-up on reopening. The app makes a separate Luna request to assess the evidence and produce a summary in the explanation language, strengths, next steps, demonstrated objective indices and a readiness recommendation.

Ending a session does not necessarily complete the curriculum lesson. Only a validated readiness result, with all objectives demonstrated and no pending retry, unlocks the next lesson. Otherwise the learner can start another practice session carrying forward learning memory and progress. The old summary and conversation remain saved. If summary generation fails, its persisted request is retried without resending a learner answer. The recap appears in saved conversation history too.

**Ordkort och bygg meningar** is available from each unlocked lesson overview and from its recap. A user-triggered Luna request generates a validated pack of 4–12 flashcards and 3–8 sentence puzzles that translate from the explanation language into the target language. Packs and progress are saved in the session, and subsequent play works offline:

- Cards reveal the target-language answer and example. “Öva igen” returns the card later in the round; “Det kunde jag” stores a known-card marker.
- Sentence puzzles offer shuffled target-language tiles, dragging or tapping to insert/remove, and dropping onto another selected tile to reorder. Duplicate word tiles have distinct identities. Keyboard/VoiceOver users can use buttons and an accessible move-first action.
- Validation checks that each accepted answer is buildable from the bank with the correct word multiplicity. Checking is local, accepts the generated alternative orders, ignores capitalization and edge punctuation, and preserves accents. Answers outside the generated alternatives are not evaluated by a model.
- Puzzle explanations, retry, optional example answers, read-aloud, completion and replay are included. These practice scores do not independently certify mastery or unlock lessons.

New session properties are optional, preserving decoding of existing version-1 snapshots. Flashcard round position and unsubmitted puzzle tile arrangements are view state; known/solved markers and generated content survive reopening.

Model messages explicitly parse Markdown emphasis, strike-through, inline code and links while preserving line breaks; the view also handles common headings, list markers and quotations. Corrections use exact word-level diffs, striking removed tokens and bolding inserted tokens. Accent, case and punctuation changes remain visible. Read-aloud strips inline Markdown syntax.

## Beginner help with Milo

**Be Milo om hjälp** is available before the learner answers in lessons, free conversations,
writing, sentence puzzles, flashcards and the pronoun game. The sheet offers **Förklara uppgiften**,
**Ge mig ett tips**, **Vad betyder det?** and **Hjälp mig komma igång**. Typing is optional;
questions may be in the explanation language or a mix of languages. The placement assessment
keeps its existing “Jag vet inte ännu” option to avoid coaching the assessment.

Opening the sheet captures the current exercise, word bank or card content, unfinished draft,
language pairing, profile and relevant lesson context. Pressing a help choice sends that snapshot
and up to six prior help exchanges to GPT-5.6 Luna through the existing user-key transport.
The model is instructed to explain in the chosen explanation language, translate examples,
explain grammar terms plainly, and leave the learner a small step to do independently.
A blank draft is explicitly supported. Follow-up questions can ask for a simpler explanation.
The explanation can also be read aloud in the chosen explanation language.

Help has its own response schema and request lifecycle. It cannot submit a learner answer,
consume lesson turns, award objectives, mark game answers or finish a lesson. The draft stays
in the exercise while the help sheet is open. After a response, the lesson or free-conversation
chat shows **Milo gav ett tips**; tapping it reopens the same tip and follow-up thread until the
learner submits the next answer. Help exchanges are not saved as assessed conversation turns. Failed
requests can be retried with the same snapshot; dismissal and credential changes cancel the
request and reject late replies. Missing credentials lead to Settings. Existing automatic
sentence hints after repeated incorrect attempts remain available.

Verification includes stub-transport coverage of Luna routing, language and exercise payload,
plus empty drafts, native-language follow-ups, bounded help history, failure/retry, cancellation,
response limits and unchanged learning progress. These tests make no live API calls and do not
establish the pedagogical quality of live Luna responses.

September 12 verification: all 91 core tests and the iOS simulator build passed. On an iPhone
18 Pro simulator, help opened from lessons, empty sentence exercises and writing; opening and
closing preserved selected words and the writing draft. All four help choices remained reachable
at the largest system Dynamic Type setting after adding scalable button styling. These UI runs
used local fixtures with no credentials. The separate macOS app build is blocked by existing
platform errors in Milo rendering, onboarding and speech; macOS UI and live Luna replies are
not verified by this change.

## Response contracts

`LearningSchema` is the source of truth for the JSON Schema sent through Responses API `text.format` with `strict: true`. `AssessmentResult` and `LessonReply` are their Codable counterparts. All model-facing instructions are English; output explanations and lesson copy are written in the learner's chosen explanation language. The assessment schema pins `profile.nativeLanguage` and `profile.targetLanguage` to the codes of the chosen course, so a result for the wrong pairing is rejected before anything is saved.

The assessment has this fixed shape (the illustrative lesson array below is abbreviated; a new plan must contain 3–8 lessons):

```json
{
  "schemaVersion": 1,
  "recommendation": "newPlan",
  "rationale": "Du kan hälsa. Vi bygger vidare med enkla vardagssamtal.",
  "profile": {
    "nativeLanguage": "sv",
    "targetLanguage": "it",
    "cefr": "A1",
    "goal": "Prata italienska på resan",
    "strengths": ["Hälsningar"],
    "focusAreas": ["Verb i presens"]
  },
  "lessons": [
    {
      "id": "greetings",
      "title": "Berätta hur du mår",
      "summary": "Hälsa och fråga hur någon mår.",
      "objectives": ["Berätta hur du mår", "Ställ en fråga"],
      "prerequisites": [],
      "vocabulary": ["ciao", "sto bene"],
      "scenario": "Un nuovo amico",
      "successCriteria": ["Svara och ställ en egen fråga"]
    }
  ]
}
```

For `continueCurrent`, `lessons` must be empty and an existing plan must exist. CEFR accepts pre-A1 through C2. Lesson prerequisites may only reference preceding lesson IDs in the same result.

Luna returns `reply` (target language), `translation` (explanation language), nullable `correction { original, corrected, explanation }`, `requiresRetry`, `retryPrompt`, zero-based `objectiveIDsAchieved`, `lessonComplete`, and replacement `memory` (maximum 3,000 characters). Semantic correctness of corrections and mastery judgments still depends on the model; schema validation does not prove pedagogical accuracy.

## Storage, privacy and failure handling

- SwiftData stores one versioned `LearningState` JSON snapshot per language, keyed by `LearningSnapshot.languageCode`, alongside the existing `LessonRecord` model. Switching language swaps in that language's snapshot and leaves the others on disk; snapshots written before language selection existed default to Italian. Practice packs saved with the older `swedish`/`italian` keys still decode, and are rewritten with the language-neutral `cue`/`answer` keys. iCloud database use is explicitly disabled. The migration test verifies an old writing record survives adding the new model.
- State is published only after a successful explicit save. Unknown versions and unreadable snapshots fail closed without resetting or overwriting data.
- Answers are persisted as pending before a network call. Retry reuses the pending answer; changing a failed/refused answer removes the pending value without duplicating history. A canceled response cannot save a late result.
- Requests use the fixed HTTPS OpenAI endpoint, an ephemeral URLSession and `store: false`. Redirects are refused. No remote conversation ID is created. This does not override OpenAI's API retention policies.
- Provider response bodies are never surfaced as errors or logged. Missing/invalid keys, model access, rate limits, refusal, incomplete responses, malformed JSON and connection failures produce actionable messages.
- Dictation and speech playback use Apple's local speech frameworks in the target language's locale; a language without an on-device dictation model reports that and leaves typing as the way in. Microphone permission and speech asset downloads occur only after tapping the microphone. Dictated text must be reviewed/sent explicitly. The full transcript is not uploaded as audio.
- There is no shared developer API key, application subscription, automatic paid retry loop, or provider fallback.

## Verification

September 14 guided-journey checks: 116 core tests passed, including production transport with simulated Responses payloads, old snapshot decoding, local scoring, support tracking, script/readiness validation, persistence and duplicate/stale attempt protection. The complete iOS Simulator Debug build passed. iPhone 17 Pro / iOS 27 checks covered the greeting flow (wrong answer, hint, correct answer, skipped speech and completion), automatic feedback scrolling, Japanese script choices at accessibility3, editable reading preferences, and visible Milo tap reactions. The experience picker and saved difficulty-feedback controls were also verified at accessibility3. The final start-card simplification and fixture wording correction received build validation; they were not separately rerun visually. Live OpenAI responses, speech quality and physical-device behavior remain unverified.

Run the production-core tests with the Xcode 27 toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/langlearn-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/langlearn-module-cache \
swift test --disable-sandbox --scratch-path /tmp/langlearn-core-build
```

The package compiles the app's actual model, service, transport, Keychain wrapper, settings and persistence sources. Tests use isolated SwiftData stores and a stub URLProtocol; they make no live API requests and do not write credentials.

Earlier implementation verification: iOS and macOS Debug builds; 30 Swift Testing tests, including parameterized API-error cases, assessment boundaries, schema validation, retries, cancellation, persistence and migration; iPhone previews of key entry, generated plan, correction/retry chat, recap, flashcards and sentence puzzles. The test runner emits sandbox-related SwiftPM cache and Core Data notification warnings; persistence and migration assertions pass.

Still requires a signed-device run with a user-entered key: Keychain save/replace/relaunch, account access to both models, a complete real assessment and Luna lesson, pedagogical quality, speech capture/playback and reassessment quality, plus live wrap-up/practice generation and physical drag-and-drop interaction. Preview fixtures are not real model responses.

## Official API references

- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [API data controls](https://developers.openai.com/api/docs/guides/your-data)
