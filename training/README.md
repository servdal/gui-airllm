# Catatan Training

Folder ini bukan jalur utama untuk aplikasi desktop lokal. Jalur utama repo sekarang adalah:

```text
Flutter desktop app -> airllm_ui.py -> model MLX lokal
```

Untuk instalasi awal, download model, menjalankan backend, dan build desktop app macOS, gunakan panduan di:

```text
../README.md
```

Ringkas:

```bash
cd /Users/duidev/htdocs/airllm
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e air_llm
python -m pip install mlx-lm mlx sentencepiece protobuf
cd local_ai_desktop
flutter pub get
flutter build macos --debug
```
