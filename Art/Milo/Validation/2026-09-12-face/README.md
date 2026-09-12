# Milo natural facial movement — 2026-09-12

Verified on the **iPhone 18 Pro simulator**, UUID `A764AF99-8DC1-43E1-A258-F9AC5EBFC30F`, in portrait. This is simulator evidence, not physical-device validation.

## Build and tests

- Xcode workspace: `LanguLearn.xcodeproj`, active scheme `LangLearn`.
- `DeviceInteractionInstallAndRun` successfully built, installed and launched the updated application, including the `facialGazePosition` easing change. The initial face-check launch was at approximately 18:58; the initial idle-check launch at approximately 18:59. Capture times are local Europe/Stockholm (CEST), not UTC.
- After the user's first request for higher resting mouth corners, the idle-only smile lift of 0.12 was rebuilt, installed and launched at approximately 19:04. A second requested increase to 0.18 (base smile 0.255) was rebuilt, installed and launched at approximately 19:10; this is the final build. Both retain the earlier eye/brow behavior.
- App state was `Running` throughout the settled captures. The initial launch capture briefly reported `RunningInBackground` before normal foreground rendering.
- `milo-tests.log` records the separate focused Swift Testing run: **19 tests passed**. The visual verifier inspected its final result; the main implementation task ran the tests.

## Visual findings

The `idle-smile-cozy-1.png` through `idle-smile-cozy-3.png` sequence is the **final idle appearance**, with the idle smile lift increased to 0.18. The files named `idle-smile-final-1.png` through `idle-smile-final-6.png` preserve the earlier 0.12 lift for comparison; despite their filenames, they are no longer the final baseline. Other screenshots document the preceding eye/gaze/brow implementation before either mouth-corner adjustment.

- Compared with the earlier `idle-smile-final-6.png`, the final cozy sequence shows another small upward lift at the mouth corners. It reads as a warmer, soft smile without becoming an exaggerated grin. The three settled captures show natural facial variation and report the app `Running`; no new rendering issue or crash was observed. This last check was deliberately limited to the requested smile adjustment.
- Compared with `idle-06.png`, the earlier 0.12-lift sequence already shows higher mouth corners and a softer resting expression. `idle-smile-final-3.png` shows its slightly stronger smile phase; `idle-smile-final-6.png` shows its more settled phase. These remain historical comparison images.
- `baseline-existing-install.png` is a close-up from the app already installed before this change, with its exact binary revision unknown. It shows the original wide white ring around the irises.
- `neutral.png` shows the new relaxed upper lids. The eyes look calmer and attentive, without looking sleepy. The main task independently inspected and accepted this amount of lid closure.
- `gaze-left.png` and `gaze-right.png` show both pupils moving together toward the respective screen side. `gaze-down.png` shows downward gaze.
- `gaze-up.png` shows upward pupils and a subtle, visible lift in both brows compared with neutral. This was captured using the studio's vertical gaze slider at **+0.186**, after the timed fixture completed. The fixture label still reads “Nollställd”; the visible slider value documents the actual manually selected gaze. The main task independently inspected and accepted the upward result.
- `blink-closed.png` shows both eyelids fully closed. `mouth-open.png` checks the independent jaw/mouth-opening control.
- `idle-01.png` through `idle-09.png` sample approximately 23 seconds with natural facial animation active, manual facial control off, zoom 3.8, and body motion paused. The sequence shows slight mouth-corner/smile changes, small brow variation, eye movements and a spontaneous blink (`idle-07.png`). These expressions are intentionally subtle.
- `look-around-0.png` through `look-around-7.png` sample approximately 15 seconds of **Tittar omkring / Idle_LookAround**, with body motion unpaused and natural facial control active. The head turns and eye gaze visibly change together: for example `look-around-3.png` turns and looks to the screen's left, while `look-around-5.png` turns/tilts toward the screen's right with upward eye direction.
- No new overlapping text, rendering failure, missing face components or app exits were observed in these checks. Studio controls remain scrollable below the fixed face preview.

Each saved screenshot has a matching `-hierarchy.txt` documenting app process, UI labels, values and hit points. Images are original device-capture files.

## Reproduction

Launch the debug scheme with `--milo-demo --milo-face-check` for neutral, mouth opening, full blink, left/right/down/up gaze and reset in five-second stages after the live rig loads. Launch with `--milo-demo --milo-idle-face-check` for a close-up with natural facial animation and paused body. To check combined movement, turn off **Pausa kroppen** and choose **Tittar omkring** in the clip picker.

All device interaction sessions were closed after their checks. The last observed app view showed the final cozy idle smile in the close-up studio, with body motion paused for comparison.
