# SteFi

Native SwiftUI macOS app based on the Synology stereo-cleanup workflow. The
Synology shell scripts remain unchanged. The GUI uses the tested Swift core to
invoke FFmpeg and ffprobe directly, without Docker, jq, or a shell command string.

## Use

1. Open the app. If FFmpeg is installed, the folder picker appears automatically.
   Otherwise an alert opens a step-by-step Homebrew installation guide.
2. Pick a folder. Only its immediate regular video files are scanned; no recursion
   and no following file symlinks.
3. Files start unchecked, including after every rescan. Check the files you want
   to process, and review each audio track's language, codec, title and rate.
   Choose a different audio track when necessary. A warning highlights selections
   that differ from the source default (e.g. Italian mono versus English stereo).
4. Process Selected (`Enter` / `Return`), or Process All (keyboard `0`). The confirmation explicitly
   asks for approval when WebM/Ogg needs an `.st.mkv` output.
5. Progress, safe cancellation, per-file failures, logs and Finder reveal are built in.

Use **Rescan (R)** to scan the current folder again or **Open Another Folder (O)**
to choose a different folder. R and O do not require the Command key.

The live statistics panel shows FFmpeg FPS, speed relative to real time, frames,
processed media time / duration, elapsed time, estimated time remaining and output
size, with separate file and batch progress. Updates arrive every 0.5 seconds from
[FFmpeg's structured progress output](https://ffmpeg.org/ffmpeg.html#Advanced-options).
FPS is processing throughput, not the video's original frame rate; missing or zero
FPS is shown as a dash. ETA is an estimate for the current file, excluding final
verification. Unknown durations/speeds do not produce invented percentages or ETAs.

Exactly one audio stream remains. Suitable two-channel audio is copied; Dolby and
DTS never qualify just because they report two channels. Otherwise only the selected
audio is encoded as AAC 320 kb/s, at the exact source sample rate. Unknown or
unsupported rates fail safely. Video, subtitles, data, attachments and chapters
are preserved when supported by the destination format. Unsupported stream/container
combinations fail rather than silently dropping streams.

The app never modifies source files, removes existing outputs, or silently changes
the source language. Default selection follows the original script; always review
the track label before processing. Language/content cannot be inferred perfectly.

New files are `name.st.ext`. Conversion happens in a unique private scratch folder
beside the source. Output is probed and checked before atomic exclusive publication
with macOS `renamex_np(RENAME_EXCL)`. A concurrently created output or dangling
symlink is never overwritten. Failed/cancelled temporary outputs are discarded.

The app build is Apple Silicon and targets macOS 14 or newer. Your separately
installed FFmpeg must support your macOS version. FFmpeg is NOT bundled; Docker
is NOT used. No NAS credentials are used. It is ad-hoc signed for local use, not
Developer ID notarized. Do not disable Gatekeeper globally.

## FFmpeg installation

The app automatically checks `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`
and its inherited PATH for both `ffmpeg` and `ffprobe`. A custom tools folder can
also be selected in the gear menu. Nothing is installed automatically.

Run these commands in Terminal one at a time:

1. If needed, install [Homebrew](https://brew.sh/):

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Follow the installer's printed **Next steps**. For the current Terminal window
   on Apple Silicon:

   ```sh
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   On Intel, use `/usr/local/bin/brew` instead.

3. Install [FFmpeg](https://formulae.brew.sh/formula/ffmpeg), which includes ffprobe:

   ```sh
   brew install ffmpeg
   ```

4. Return to the app and click **Check Again**. The app's guide includes Copy
   buttons, Open Terminal, and links to these official websites.

## Versioning

The app name is always **SteFi** and its filename is always **SteFi.app**.
Version numbers are internal metadata, not part of the filename or window header.

`VERSION` and `BUILD_NUMBER` are persistent project metadata. First release: 1.0.0.
Each successful new release packaging increments the patch: 1.0.1, 1.0.2, etc.
Version state is not based on an existing `.app`, so moving/deleting an app does
not reset it. Failed packaging does not advance the version. `--same-version` is
reserved for internal pre-release QA.

## Build and verify

Open **SteFi.xcodeproj** in Xcode, select the shared **SteFi** scheme and **My Mac**,
then use Run (Command-R) or Test (Command-U). The project includes the macOS app,
the statically linked StereoCore library, and both existing test targets. Xcode
uses the same Swift files as the optional Swift Package; no source copies are required.
Hosted unit tests suppress the launch folder picker.

The checked-in project requires Xcode 15 or newer and builds for Apple Silicon,
with a macOS 14 deployment target. Local signing uses an ad-hoc signature and
does not require an Apple Developer team. The app needs access to the selected
media folder and installed FFmpeg binaries, so the App Sandbox is disabled.

To test and build a new release from Terminal:

```sh
xcodebuild -project SteFi.xcodeproj -scheme SteFi -destination 'platform=macOS,arch=arm64' -derivedDataPath build/XcodeDerivedData test
python3 Packaging/package_app.py
```

The release script builds the Xcode Release scheme, creates `dist/SteFi.app`
with its icon and internal version metadata, then signs and validates it.
After a successful release it synchronizes `Config/Version.xcconfig` with
`VERSION` and `BUILD_NUMBER`, so subsequent Xcode Run builds use the same version.
Previous builds are retained
under `dist/archive/`, also with the filename `SteFi.app`. No FFmpeg binaries or libraries
are copied into the app. No ZIP is created. No global installation or Homebrew
changes are made.

`Resources/AppIcon.icns` is the existing display-and-two-speakers icon.
`Packaging/make_icon.swift` can regenerate it. After adding or removing Swift files,
run `python3 Packaging/generate_xcode_project.py` to refresh the checked-in project;
Xcode is ready to use without running this generator first.

Tests include DTS stereo, default-track warnings, sample rates, literal filenames,
non-recursive scanning, stream-copy hashes, multiple subtitles, attachments,
chapters, cancellation cleanup, MKV consent, source changes and output collisions.
Set `STEREO_TEST_TOOLS=/path/to/tools` to test a different installed FFmpeg.

Media processing continues with other selected files after a failure. The active
conversion prevents automatic idle system sleep, but lid closure or manual sleep
can suspend it. Quitting/closing while active offers safe cancellation first.
