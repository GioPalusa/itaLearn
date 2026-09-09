# Adaptive Italian learning

ItaLearn now uses a user-provided OpenAI API key, GPT-5.6 Sol for placement and planning, and GPT-5.6 Luna for teaching. Swedish remains the learner's explanation language and Italian the target language. The existing Apple-model dependency and Private Cloud Compute entitlement have been removed.

## Implemented flow

1. At startup, the learner enters their own API key. Settings supports replacing or removing it. Keys are stored with Keychain Services, `WhenUnlockedThisDeviceOnly`, with synchronisation disabled. No key is bundled, saved in preferences, or written to learning records. Key entry checks format; the first model request verifies actual API access.
2. A local welcome opens a six-question written placement chat. After each of the first five answers Sol generates one adaptive follow-up. The learner can say they do not know. After answer six, Sol returns a strict JSON assessment; there is no seventh question.
3. The app validates the version, languages, estimated level, lesson counts, IDs, prerequisites and required content before saving anything. It retains the original response JSON and renders the returned lessons as the study plan. This is an informal estimate of written ability, not a certified CEFR assessment or an assessment of pronunciation.
4. Luna receives the learner profile, the selected lesson, achieved objective indices, a compact pedagogical summary and at most 16 recent messages. It corrects errors, explains them in Swedish, and asks for another attempt when needed. Each reply replaces the compact learning summary so important errors and the current task survive context trimming.
5. The app refuses replies that simultaneously request a retry and award objectives or finish a lesson. Opening turns cannot award progress. A separate wrap-up assessment determines mastery from demonstrated objectives and success criteria, after at least two learner answers and with no unresolved retry. Prerequisites determine which lessons are available.
6. Reassessment uses the six new answers, the current plan/progress and up to six recent lesson summaries. `continueCurrent` updates the profile while preserving plan identity, lesson progress and conversations. `newPlan` archives the old plan and starts the returned plan. Every assessment and previous conversation remains available in Mitt lärande.

## Lesson endings and practice (September 9)

A session wraps up when all objective indices have been credited, after eight learner answers (including retries), when the teacher signals completion, or when the learner chooses **Avsluta och sammanfatta** after two answers. Long conversations saved by the previous version also reach wrap-up on reopening. The app makes a separate Luna request to assess the evidence and produce a Swedish summary, strengths, next steps, demonstrated objective indices and a readiness recommendation.

Ending a session does not necessarily complete the curriculum lesson. Only a validated readiness result, with all objectives demonstrated and no pending retry, unlocks the next lesson. Otherwise the learner can start another practice session carrying forward learning memory and progress. The old summary and conversation remain saved. If summary generation fails, its persisted request is retried without resending a learner answer. The recap appears in saved conversation history too.

**Ordkort och bygg meningar** is available from each unlocked lesson overview and from its recap. A user-triggered Luna request generates a validated pack of 4–12 flashcards and 3–8 Swedish-to-Italian sentence puzzles. Packs and progress are saved in the session, and subsequent play works offline:

- Cards reveal the Italian translation and example. “Öva igen” returns the card later in the round; “Det kunde jag” stores a known-card marker.
- Sentence puzzles offer shuffled Italian tiles, dragging or tapping to insert/remove, and dropping onto another selected tile to reorder. Duplicate word tiles have distinct identities. Keyboard/VoiceOver users can use buttons and an accessible move-first action.
- Validation checks that each accepted answer is buildable from the bank with the correct word multiplicity. Checking is local, accepts the generated alternative orders, ignores capitalization and edge punctuation, and preserves accents. Answers outside the generated alternatives are not evaluated by a model.
- Puzzle explanations, retry, optional example answers, read-aloud, completion and replay are included. These practice scores do not independently certify mastery or unlock lessons.

New session properties are optional, preserving decoding of existing version-1 snapshots. Flashcard round position and unsubmitted puzzle tile arrangements are view state; known/solved markers and generated content survive reopening.

Model messages explicitly parse Markdown emphasis, strike-through, inline code and links while preserving line breaks; the view also handles common headings, list markers and quotations. Corrections use exact word-level diffs, striking removed tokens and bolding inserted tokens. Accent, case and punctuation changes remain visible. Read-aloud strips inline Markdown syntax.

## Response contracts

`LearningSchema` is the source of truth for the JSON Schema sent through Responses API `text.format` with `strict: true`. `AssessmentResult` and `LessonReply` are their Codable counterparts. All model-facing instructions are English; output explanations and lesson copy are Swedish.

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

Luna returns `italian`, `swedish`, nullable `correction { original, corrected, explanation }`, `requiresRetry`, `retryPrompt`, zero-based `objectiveIDsAchieved`, `lessonComplete`, and replacement `memory` (maximum 3,000 characters). Semantic correctness of corrections and mastery judgments still depends on the model; schema validation does not prove pedagogical accuracy.

## Storage, privacy and failure handling

- SwiftData stores a versioned `LearningState` JSON snapshot alongside the existing `LessonRecord` model. iCloud database use is explicitly disabled. The migration test verifies an old writing record survives adding the new model.
- State is published only after a successful explicit save. Unknown versions and unreadable snapshots fail closed without resetting or overwriting data.
- Answers are persisted as pending before a network call. Retry reuses the pending answer; changing a failed/refused answer removes the pending value without duplicating history. A canceled response cannot save a late result.
- Requests use the fixed HTTPS OpenAI endpoint, an ephemeral URLSession and `store: false`. Redirects are refused. No remote conversation ID is created. This does not override OpenAI's API retention policies.
- Provider response bodies are never surfaced as errors or logged. Missing/invalid keys, model access, rate limits, refusal, incomplete responses, malformed JSON and connection failures produce actionable messages.
- Italian dictation and speech playback use Apple's local speech frameworks. Microphone permission and speech asset downloads occur only after tapping the microphone. Dictated text must be reviewed/sent explicitly. The full transcript is not uploaded as audio.
- There is no shared developer API key, application subscription, automatic paid retry loop, or provider fallback.

## Verification

Run the production-core tests with the Xcode 27 toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/italearn-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/italearn-module-cache \
swift test --disable-sandbox --scratch-path /tmp/italearn-core-build
```

The package compiles the app's actual model, service, transport, Keychain wrapper, settings and persistence sources. Tests use isolated SwiftData stores and a stub URLProtocol; they make no live API requests and do not write credentials.

Verified during implementation: iOS and macOS Debug builds; 30 Swift Testing tests, including parameterized API-error cases, assessment boundaries, schema validation, retries, cancellation, persistence and migration; iPhone previews of key entry, generated plan, correction/retry chat, recap, flashcards and sentence puzzles. The test runner emits sandbox-related SwiftPM cache and Core Data notification warnings; persistence and migration assertions pass.

Still requires a signed-device run with a user-entered key: Keychain save/replace/relaunch, account access to both models, a complete real assessment and Luna lesson, pedagogical quality, speech capture/playback and reassessment quality, plus live wrap-up/practice generation and physical drag-and-drop interaction. Preview fixtures are not real model responses.

## Official API references

- [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [GPT-5.6 Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [API data controls](https://developers.openai.com/api/docs/guides/your-data)
