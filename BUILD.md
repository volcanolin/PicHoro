# PicHoro build notes (fork / fix branch)

This fork is based on upstream [Kuingsmile/PicHoro](https://github.com/Kuingsmile/PicHoro) `main`
(including the Impeller-off fix in `AndroidManifest.xml`).

## Why this fork exists

1. Official release `v3.0.1` still enables Impeller; on some devices (e.g. Xiaomi 15 / HyperOS)
   opening the **仓库** tab can freeze the whole phone (Vulkan / `libflutter.so` crash).
   Upstream main already sets:
   `io.flutter.embedding.android.EnableImpeller=false` but has not shipped a new APK.
2. Building upstream main with current Flutter stable needs a few plugin/toolchain fixes.

## What we changed

### App / Android

| File | Change |
|------|--------|
| `android/app/src/main/AndroidManifest.xml` | Impeller disabled (from upstream) + OTA provider |
| `android/app/src/main/res/xml/filepaths.xml` | FileProvider paths for OTA |
| `android/app/build.gradle` | Optional release keystore; fallback to debug signing; arm64 filter; compileSdk 36 |
| `android/build.gradle` | Force plugin `compileSdkVersion 36` / Kotlin `jvmTarget 17` |
| deleted `mipmap-hdpi/favicon.jpg` | Duplicate resource with `favicon.png` |

### Vendored plugins (`third_party/`)

Published plugins were copied and patched so a clean `git clone` + `flutter build apk` works:

| Package | Patch |
|---------|--------|
| `third_party/ota_update` | `compileSdkVersion 36` + `namespace` (was 28 → `android:attr/lStar` fail) |
| `third_party/receive_intent` | Null-safe `SigningInfo` / signatures (Kotlin 2.x) |
| `third_party/syncfusion_flutter_pdfviewer` | Removed Flutter embedding v1 `registerWith` |
| `third_party/syncfusion_flutter_pdf` | Vendored with viewer for offline builds |

`pubspec.yaml` points these four deps at `path: third_party/...`.

## Build (Android arm64 release)

```bash
# Flutter 3.32+ / JDK 17 or 21 / Android SDK 36 recommended
flutter pub get
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
```

- Without `android/key.properties`, release build is **debug-signed** (fine for personal installs).
- Package id remains `com.example.horopic` → cannot overwrite an officially signed install; uninstall first.
- `--no-tree-shake-icons` is required because of non-const `IconData` in `home_page.dart`.

## Signing

Official keystore is **not** in the public repo. Options:

1. Debug / fallback signing (default here) — personal testing.
2. Create your own `android/key.properties` + `.jks` for a private release key.
3. Wait for upstream release if you need the author's signature.

## Config note after reinstall

Switching signing keys requires uninstall. That wipes local figure-bed configs under
`app_flutter/*_config.txt`. Re-import or re-enter credentials after install.
