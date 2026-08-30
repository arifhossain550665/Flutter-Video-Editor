# Flutter Video Editor

A production-ready video editor: import clips, trim each one precisely,
reorder and merge them, overlay background audio with noise cancellation
and volume boosting, and export straight to the device gallery.

## What's in this package

```
pubspec.yaml                                 -> all dependencies
ios/Runner/Info.plist                        -> iOS permission keys
android/app/src/main/AndroidManifest.xml     -> Android permissions
lib/
  main.dart                                  -> app entry point
  models/video_clip.dart                     -> clip + trim range model
  services/media_service.dart                -> picking, temp files, gallery save
  services/ffmpeg_service.dart               -> trim / concat / audio-mix FFmpeg pipeline
  controllers/editor_controller.dart         -> app state + export orchestration
  views/home_screen.dart                     -> import screen
  views/editor_screen.dart                   -> clip list, audio, export
  views/trim_screen.dart                     -> per-clip trim UI with preview
  widgets/clip_tile.dart                     -> row in the clip list
  widgets/progress_dialog.dart               -> export progress UI
```

## Setup

1. **Create the Flutter shell** (skip this if you already have a Flutter
   project you're pasting these files into):

   ```bash
   flutter create --org com.yourcompany flutter_video_editor
   cd flutter_video_editor
   ```

2. **Copy every file above into the matching path**, overwriting the
   generated `pubspec.yaml`, `ios/Runner/Info.plist` and
   `android/app/src/main/AndroidManifest.xml`, and replacing the generated
   `lib/main.dart` / adding the rest of `lib/`.

3. **Bump the Android minSdkVersion.** `ffmpeg_kit_flutter_new` requires API
   24+. Open `android/app/build.gradle` (or `build.gradle.kts`) and set:

   ```gradle
   defaultConfig {
       minSdkVersion 24
       // ...
   }
   ```

4. **Install dependencies:**

   ```bash
   flutter pub get
   ```

5. **iOS only** - install CocoaPods dependencies and set the deployment
   target to iOS 13+ in `ios/Podfile` (uncomment and set
   `platform :ios, '13.0'`), then:

   ```bash
   cd ios && pod install && cd ..
   ```

6. **Run it:**

   ```bash
   flutter run
   ```

## How the export pipeline works

`EditorController.exportVideo()` runs four FFmpeg stages back to back,
reporting weighted progress (50% / 15% / 25% / 10%) through
`overallProgress` so the UI can show one continuous progress bar:

1. **Trim + normalize** - every clip is cut to its selected start/end,
   scaled/padded to 1280x720 @ 30fps, and re-encoded with H.264/AAC. This
   normalization step is what makes it safe to stream-copy-concatenate
   clips from different source videos in step 2.
2. **Concat** - the normalized clips are joined with FFmpeg's concat
   demuxer (fast stream copy, no re-encode).
3. **Mix background audio** *(only if you added one)* - the background
   track is optionally denoised with `afftdn`, boosted with the `volume`
   filter (100%-300%), passed through a limiter so the boost never clips,
   and mixed with the video's original audio (or replaces it if the video
   is silent).
4. **Save to gallery** - the final file is written into a "Video Editor"
   album via `gal`, after requesting photo library permission.

## Customizing

- **Noise reduction strength**: tweak the `nf=-25` value passed to
  `afftdn` in `ffmpeg_service.dart` (more negative = more aggressive).
  If you'd rather use RNN-based noise suppression (`arnndn`), you'll need
  to bundle a `.rnnn` model file with the app and pass its path with
  `arnndn=m=/path/to/model.rnnn` instead - `afftdn` was used here because
  it needs no external model file.
- **Export resolution/fps**: change `_targetWidth`, `_targetHeight`,
  `_targetFps` at the top of `FFmpegService`.
- **Volume boost range**: the UI slider is capped at 100-300% to match the
  spec; the service itself clamps to 10-300% (`0.1x`-`3.0x`).
# Flutter-Video-Editor
