# Local Coding AI Desktop

Repo ini menyiapkan AI coding lokal untuk MacBook Apple Silicon. Backend inference berjalan lewat Python (`airllm_ui.py`) dan aplikasi desktop macOS dibuat dengan Flutter (`local_ai_desktop`).

Model default yang dipakai:

```text
models/Qwen2.5-Coder-7B-Instruct-4bit
```

Model tersebut adalah model MLX 4-bit untuk coding lokal. Cocok untuk MacBook Air 16 GB karena ukuran model sekitar 4 GB.

## Struktur

```text
.
├── airllm_ui.py                 # Server lokal Python, endpoint /health dan /ask
├── air_llm/                     # Paket AirLLM lokal
├── local_ai_desktop/            # Aplikasi Flutter desktop macOS
├── models/                      # Model lokal, tidak masuk git
└── .venv/                       # Python virtual environment, tidak masuk git
```

## Download Repo

Clone repo ke folder kerja:

```bash
cd /Users/duidev/htdocs
git clone <repo-url> airllm
cd airllm
```

Jika repo sudah ada, cukup masuk ke foldernya:

```bash
cd /Users/duidev/htdocs/airllm
```

## Instalasi Awal Python

Buat virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
```

Install paket lokal dan dependency inference:

```bash
python -m pip install -e air_llm
python -m pip install mlx-lm mlx sentencepiece protobuf
```

Tes dependency dasar:

```bash
python - <<'PY'
import mlx
import mlx_lm
import sentencepiece
print("python inference dependency ok")
PY
```

## Download Model

Model coding yang direkomendasikan untuk MacBook Air 16 GB:

```text
mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
```

Download ke folder lokal:

```bash
source .venv/bin/activate
python - <<'PY'
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
    local_dir="models/Qwen2.5-Coder-7B-Instruct-4bit",
)
PY
```

Pastikan file utama ada:

```bash
ls models/Qwen2.5-Coder-7B-Instruct-4bit/model.safetensors
ls models/Qwen2.5-Coder-7B-Instruct-4bit/tokenizer.json
ls models/Qwen2.5-Coder-7B-Instruct-4bit/config.json
```

## Jalankan Backend Python

Backend lokal berjalan di `127.0.0.1:7860`.

```bash
source .venv/bin/activate
python airllm_ui.py
```

Cek status:

```bash
curl http://127.0.0.1:7860/health
```

Kirim pertanyaan manual:

```bash
curl -X POST http://127.0.0.1:7860/ask \
  -H 'Content-Type: application/json' \
  -d '{
    "backend": "mlx_lm",
    "model_id": "/Users/duidev/htdocs/airllm/models/Qwen2.5-Coder-7B-Instruct-4bit",
    "prompt": "Buatkan fungsi Dart untuk validasi email.",
    "max_new_tokens": 700,
    "max_length": 2048
  }'
```

## Komunikasi Flutter Dengan Python

Alur komunikasi aplikasi desktop:

```text
Flutter desktop app
  ├─ menjalankan .venv/bin/python airllm_ui.py
  ├─ membaca stdout/stderr sebagai log di halaman Settings
  ├─ cek backend lewat GET http://127.0.0.1:7860/health
  └─ kirim prompt lewat POST http://127.0.0.1:7860/ask
        ↓
Python airllm_ui.py
  ├─ load model MLX-LM dari folder models/
  ├─ generate jawaban lokal memakai Metal GPU
  └─ balas JSON ke Flutter
```

Payload utama dari Flutter:

```json
{
  "backend": "mlx_lm",
  "model_id": "/Users/duidev/htdocs/airllm/models/Qwen2.5-Coder-7B-Instruct-4bit",
  "prompt": "pertanyaan user",
  "max_new_tokens": 700,
  "max_length": 2048
}
```

Response sukses:

```json
{
  "answer": "jawaban model"
}
```

Response error:

```json
{
  "error": "pesan error"
}
```

## Aplikasi Desktop Flutter

Folder aplikasi:

```bash
cd local_ai_desktop
```

Install dependency Flutter:

```bash
flutter pub get
```

Validasi kode:

```bash
flutter analyze
flutter test
```

Jalankan saat development:

```bash
flutter run -d macos
```

Build desktop app debug:

```bash
flutter build macos --debug
```

Jika build via Flutter bermasalah karena Xcode workspace di environment tertentu, gunakan build project langsung:

```bash
xcodebuild \
  -project macos/Runner.xcodeproj \
  -scheme Runner \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Hasil debug app:

```text
local_ai_desktop/build/DerivedData/Build/Products/Debug/Local Coding AI.app
```

Buka aplikasi:

```bash
open "local_ai_desktop/build/DerivedData/Build/Products/Debug/Local Coding AI.app"
```

## Cara Pakai Desktop App

1. Buka `Local Coding AI.app`.
2. Masuk ke halaman Settings.
3. Pastikan Working folder mengarah ke:

```text
/Users/duidev/htdocs/airllm
```

4. Pastikan Model aktif mengarah ke:

```text
/Users/duidev/htdocs/airllm/models/Qwen2.5-Coder-7B-Instruct-4bit
```

5. Klik `Jalankan airllm_ui.py`.
6. Buka halaman Chat.
7. Tulis pertanyaan coding di input bawah.
8. Jawaban muncul di area percakapan.

## Download Model Dari Desktop App

Di halaman Settings:

1. Isi Hugging Face repo, contoh:

```text
mlx-community/Qwen2.5-Coder-7B-Instruct-4bit
```

2. Isi folder tujuan, contoh:

```text
models/Qwen2.5-Coder-7B-Instruct-4bit
```

3. Klik `Download dan Switch`.

Jika download sukses, app otomatis mengganti Model aktif ke folder baru. Jika download gagal atau file model tidak lengkap, app tetap memakai model lama.

## Git Actions Di Desktop App

Panel kanan Chat menjalankan perintah git pada Working folder:

```text
Status     -> git status --short
Diff       -> git diff --stat
Branch     -> git branch --show-current
Stage All  -> git add -A
Commit     -> git commit -m "<pesan commit>"
```

Output git tampil di panel kanan.

## Catatan MacBook Apple Silicon

MLX membutuhkan akses Metal GPU. Jika backend dijalankan dari sandbox/headless, error ini bisa muncul:

```text
[metal::load_device] No Metal device available
```

Solusinya: jalankan app atau backend dari sesi macOS biasa, bukan dari environment headless yang tidak punya akses Metal.

## File Yang Tidak Masuk Git

File berikut sengaja di-ignore:

```text
.venv/
.flutter_home/
models/
local_ai_desktop/build/
__pycache__/
```

Model berukuran besar dan dependency lokal tidak perlu masuk repository.
