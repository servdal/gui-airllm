# AirLLM Package Lokal

Folder ini berisi paket Python `airllm` yang di-install secara editable oleh repo induk.

## Instalasi

Dari root repo:

```bash
cd /Users/duidev/htdocs/airllm
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e air_llm
python -m pip install mlx-lm mlx sentencepiece protobuf
```

## Peran Dalam Aplikasi

Untuk MacBook Apple Silicon, aplikasi desktop memakai backend `mlx_lm` melalui `airllm_ui.py`. Paket `airllm` tetap disiapkan untuk kompatibilitas dan opsi backend AirLLM.

Alur utama:

```text
local_ai_desktop
  -> menjalankan ../airllm_ui.py
  -> airllm_ui.py memakai model lokal di ../models/
  -> jawaban dikirim balik ke Flutter via JSON
```

Panduan lengkap ada di `../README.md`.
