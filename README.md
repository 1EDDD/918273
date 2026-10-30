# Tendies Studio

Native SwiftUI iPhone/iPad app that converts MOV and MP4 videos into `.tendies` packages.

## Build from GitHub (no local Mac required)

Every push to `main` runs the `Build unsigned iOS IPA` workflow on a hosted macOS runner. When it succeeds, open **Actions**, select the latest build, and download the `TendiesStudio-unsigned-IPA` artifact. Extract that artifact ZIP to get `TendiesStudio-unsigned.ipa`.

The IPA is built without an Apple Developer signing certificate. It is intended for compatible workflows such as TrollStore or LiveContainer; it is not App Store-ready and may need signing for conventional sideloading tools.

## App features

- Import MOV / MP4 videos from Files.
- Set wallpaper name, target dimensions, FPS, scale, and identifier.
- Extract video frames and encode them as JPEG.
- Generate the Tendies descriptor hierarchy and package it as `.tendies`.
- Share the generated `.tendies` file from the iOS share sheet.

## Compatibility note

The converter ports the package layout and metadata from `22amiibo/mp4To.Tendies/script.py`. A successful build only verifies the app compiles; it does not guarantee that every generated wallpaper imports on every iOS version. Validate the output with the target PosterBoard workflow.

For initial testing, use a short 3–5 second clip at 15–30 FPS. Long videos and high frame rates can produce very large archives.
