# Local Coding AI Desktop

Ini adalah aplikasi Flutter desktop macOS untuk menjalankan AI coding lokal dari repo induk.

## Alur Kerja

```text
Flutter app
  -> menjalankan ../.venv/bin/python ../airllm_ui.py
  -> membaca log proses
  -> GET /health
  -> POST /ask
  -> menampilkan jawaban model
```

Backend Python tetap berada di repo induk:

```text
../airllm_ui.py
```

Model default:

```text
../models/Qwen2.5-Coder-7B-Instruct-4bit
```

## Jalankan Saat Development

```bash
cd /Users/duidev/htdocs/airllm/local_ai_desktop
flutter pub get
flutter run -d macos
```

## Validasi

```bash
flutter analyze
flutter test
```

## Build Desktop App

```bash
flutter build macos --debug
```

Fallback jika perlu build langsung lewat Xcode:

```bash
xcodebuild \
  -project macos/Runner.xcodeproj \
  -scheme Runner \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Hasil app:

```text
build/DerivedData/Build/Products/Debug/Local Coding AI.app
```

Buka:

```bash
open "build/DerivedData/Build/Products/Debug/Local Coding AI.app"
```

Panduan lengkap instalasi repo, download model, dan komunikasi Flutter-Python ada di `../README.md`.
