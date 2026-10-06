# SteFi verification

## 1.0.3 (build 4)

- Built successfully as `dist/SteFi.app`; version appears only in bundle metadata.
- Strict code-signature validation passed.
- 25 Swift tests and 2 stable-package-name tests passed.
- Apple Silicon arm64 executable with macOS 14 deployment target.
- No bundled FFmpeg, ffprobe, Helpers directory or third-party Frameworks directory.

## 1.0.2 verification

- Version 1.0.2 (build 3): release build and strict code-signature validation passed.
- 25 automated tests passed, including new default-selection, explicit-selection
  and real scan/rescan selection-reset tests.
- Actual app UI: all three candidates initially unchecked; Process Selected disabled.
- Return and keypad Enter with no selection left the window unchanged.
- With exactly one file checked, both Return and keypad Enter opened the
  confirmation for exactly one file. Tests cancelled these dialogs without processing.
- Plain R rescanned and reset all checkboxes. Plain O opened the folder picker.
- Both labelled buttons are visible in the main window; layout visually checked.

## Previous media-processing verification (1.0.1)

Validated on an Apple Silicon Mac with locally installed Homebrew FFmpeg 9.0.1.

- `swift test`: 22 tests passed, 0 failures, including 8 real-media integration tests.
- Release build: native arm64 executable, deployment target macOS 14.
- `codesign --verify --deep --strict`: passed, ad-hoc local signature.
- Bundle contains only the SteFi executable, resources and metadata; no FFmpeg,
  ffprobe or copied third-party libraries. No Docker, installation or Homebrew
  modification was performed.
- UI: automatic folder picker, scan, selection clearing, Process All, Process
  Selected, language/MKV confirmation, successful completion, installation guide
  and Check Again checked in the actual native app.
- UI progress on generated 20-minute AC3 5.1 test: 1795 FPS, 74.8x, 44.0%, elapsed
  7 seconds, remaining estimate 8 seconds, output 19.1 MB during conversion.
  Final output: MPEG-4 video copied, exactly one AAC 2-channel audio stream at
  the original 48000 Hz; output duration 1200.016 seconds.
- Short DTS stereo fixture became AAC stereo at its original 44100 Hz.
- Tests compare original file hashes and copied packet hashes, retain multiple
  subtitles/attachments/chapters, protect existing files and dangling symlinks,
  refuse changed sources and remove only owned temporary files after cancellation.
- Missing tool detection and invalid/unknown progress values are tested without
  removing or changing the real installed FFmpeg tools.

This is not a full-length film compatibility guarantee. Unusual stream/container
combinations may fail safely. macOS 14 is the deployment target, not a tested OS
matrix. The app is not Developer ID notarized.
