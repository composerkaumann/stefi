# Changelog

## 1.0.4

- Add a native SteFi.xcodeproj with a shared Run/Test scheme, app target, static
  StereoCore library and both existing test targets.
- Release packaging now builds through Xcode; version settings are synchronized
  with the persistent internal version files after a successful release.
- Include the existing app icon and Info.plist in the Xcode project.
- Hosted tests skip interactive startup panels.

## 1.0.3

- App name and filename remain SteFi / SteFi.app; versions stay in internal metadata.
- Remove the version suffix beside the window heading.
- Future builds retain the previous SteFi.app in an internal archive folder.

## 1.0.2

- Files start unchecked after folder selection and every rescan.
- Visible Open Another Folder (O) and Rescan (R) buttons; plain keys, no Command.
- Process Selected is the Return / keypad Enter default action and stays disabled with no selection.

## 1.0.1 — SteFi

- Name and app identity changed to SteFi; icon shows a display between two speakers.
- Live FFmpeg statistics: FPS, frames, speed, media time, elapsed time, estimated
  remaining time, output size, file progress and overall batch progress.
- Verification is a distinct phase; a file is complete only after validation and
  safe publication. Missing statistics are displayed as unavailable.
- FFmpeg and ffprobe remain external. Missing-tool alert includes a Homebrew guide,
  including Homebrew installation, copyable commands and Check Again.

## 1.0.0 — Initial native app

- Nonrecursive folder scan and numbered selection, with selected/all processing.
- Preserve suitable stereo; convert Dolby/DTS and other unsuitable audio to AAC
  stereo at 320 kb/s, explicitly keeping the source sample rate.
- Preserve video/subtitles; validate outputs; never overwrite source or destination.
- Audio-track picker and language warnings; explicit MKV container consent.
- Cancellation, processing logs and Finder reveal.
