# Milo placement validation — 12 September 2026

Device verification used a separate iPhone 17e simulator (iOS 27, 390 × 844 points, UUID `1520DAE8-5A2C-49C5-897E-75FDB0BC8CD3`). The workspace-backed device session `Milo Placement QA Final` was closed after verification. Reduce Motion was changed through Settings and restored to its original off state; `reduce-motion-restored.txt` records value 0.

## Final appearance and interactions

Each PNG has a matching accessibility hierarchy TXT. Files named `*-final` show the final appearance. Other captures are explicitly intermediate evidence and may show earlier avatar sizes, a circular portrait, or the earlier missing sentence portrait. They are retained to explain the fixes, not as the final design. Initial blank launch captures were overwritten with settled captures.

| Evidence | Verified result |
| --- | --- |
| `plan-final.png`, `plan-tip-final.png` | Large unframed Milo torso sits flush in the greeting card. Tap changes the study tip; card height remains 156 points and neighboring content stays in place. Text is readable without overlap. |
| `overview-final.png` | Larger upper body appears behind the lesson summary. Full hair is visible after the crop fix; no overlap with the summary. |
| `sentence-final.png` | A readable unframed bust uses the space below the exercise. Word-bank and action positions remain unchanged: Check center y509 and Reset center y556. Portrait ends above the tab bar. |
| `flashcards-final.png` | Milo peers over the card edge; question, rating buttons, and swipe instructions all fit above the tab bar. |
| `chat-speaking-focus-final.png` | Tapping Listen then immediately focusing the composer preserves the narration stop control. Hierarchy confirms a 44 × 44 point Stop button and keyboard focus. Tapping Stop removes narration controls while leaving the keyboard focused. |
| `onboarding-welcome-final.png` | Welcome artwork, headline, explanation and primary action fit. The primary action navigates to language selection. |
| `onboarding-language-guide-final.png` | Unframed guide portrait sits beside its speech bubble; no hair or text clipping. |
| `onboarding-language-final.png` | Selected-language fixture scrolls to native-language/name controls; Continue remains visible. |
| `practice-empty-reduce-motion-final.png` | With the real Reduce Motion setting enabled, the full standing character is replaced by an unframed compact portrait. Text/actions remain in place. |

## Additional functional and layout evidence

- `sentence-retry.png` and `sentence-correct.png`: selecting an incomplete sentence produces retry feedback; adding the remaining correct words and checking produces success. Both feedback layouts and controls remain readable. No model request was used.
- `flashcards-answer.png`: tapping the card reveals readable Italian answer and local narration control.
- `progress-compact.png`: populated progress chart and strengths card are readable; Milo peeks over the strengths card and additional history is below the fold.
- `pronoun-active.png`, `pronoun-completed.png`: active and completed seeded game layouts are readable. Tapping `io` produces correct feedback and increments the streak.
- `practice-empty-compact.png`: full standing Milo occupies unused bottom space without covering the generation button or explanatory copy.
- `practice-empty-ax3.png`: accessibility size 3 enlarges semantic text, allows scrolling, and removes the decorative stage.
- `sentence-ax3.png`, `flashcards-ax3.png`: existing fixed `.il` fonts remain the same size at accessibility size 3. These captures confirm no new overlap, but do **not** demonstrate full Dynamic Type support on these surfaces. The pre-existing font system was not changed as part of Milo placement.

## Reproduction and boundaries

DEBUG fixture routes use `--milo-placement-preview --milo-placement-screen <screen>`, optionally `--milo-placement-large-text` for accessibility size 3. Screen values: `chat`, `sentence`, `sentence-hint`, `flashcards`, `plan`, `progress`, `overview`, `practice-empty`, `practice-ready`, `pronoun-intro`, `pronoun-active`, `pronoun-completed`, `writing`.

Fixtures render production views under the actual three-tab structure and seeded navigation stacks. They use an in-memory learner container and a dedicated settings suite. Seeded chat messages avoid automatic model generation; the access object does not load credentials. Verification used local word/card/pronoun interactions, narration and navigation. Generation, send, microphone permission and API-key actions were not exercised. Not every available fixture route was visually tested.

Onboarding uses `--onboarding-preview`, with `--onboarding-language` and optionally `--onboarding-selected`. Reduce Motion must be set through simulator Accessibility settings; it is not overridden by a launch argument.

This report covers simulator UI and interaction behavior. It does not claim physical-device testing, live AI responses, speech-input recognition, network availability, or a full accessibility audit. Build and core-test results are reported separately by the implementing task.

## Follow-up: extend the sentence portrait below the safe area

The newest sentence appearance is `sentence-body-initial.png` with its matching hierarchy. Compared with `sentence-final.png`, the hair remains at approximately y633 with the same apparent head scale. More torso, arms and jeans are visible downward behind the translucent tab bar and beyond the bottom edge. The exercise remains unchanged: word targets y392/444, Check y509, Reset y555.7, and tab targets y792.

Tapping the selected Öva tab at (195.2, 792), directly over the extended body, successfully returns to the Öva root (`sentence-body-tab-tap.png` and TXT). Re-entering Bygg meningar through that root works, and selecting a word still moves it into the sentence. The body overlay does not intercept the tab touch. This follow-up used the same separate simulator; the workspace-backed `Milo Extended Body QA` session was closed after verification. No system accessibility settings were changed during this follow-up.
