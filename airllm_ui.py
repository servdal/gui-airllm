#!/usr/bin/env python3
"""
Small local web UI for asking questions through AirLLM.

Run:
    python airllm_ui.py

Then open:
    http://127.0.0.1:7860
"""

from __future__ import annotations

import json
import platform
import sys
import traceback
from html import escape
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Any
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
LOCAL_PACKAGE = ROOT / "air_llm"
if str(LOCAL_PACKAGE) not in sys.path:
    sys.path.insert(0, str(LOCAL_PACKAGE))


DEFAULT_MODEL = str(ROOT / "models" / "Qwen2.5-Coder-7B-Instruct-4bit")
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 7860


class ModelState:
    def __init__(self) -> None:
        self.lock = Lock()
        self.model = None
        self.cache_key: tuple[Any, ...] | None = None


STATE = ModelState()


HTML = """
<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Local Coding AI</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f7f8;
      --panel: #ffffff;
      --text: #172026;
      --muted: #5c6a72;
      --line: #d8e0e4;
      --accent: #0f766e;
      --accent-dark: #0b5f59;
      --danger: #b42318;
      --answer: #eef7f5;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      background: var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    main {
      width: min(1080px, calc(100% - 32px));
      margin: 0 auto;
      padding: 32px 0;
    }

    header {
      display: flex;
      align-items: end;
      justify-content: space-between;
      gap: 20px;
      margin-bottom: 20px;
    }

    h1 {
      margin: 0 0 6px;
      font-size: clamp(28px, 4vw, 44px);
      line-height: 1.05;
      letter-spacing: 0;
    }

    .subtitle {
      margin: 0;
      color: var(--muted);
      font-size: 15px;
    }

    .status {
      min-width: 160px;
      padding: 8px 12px;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      color: var(--muted);
      font-size: 13px;
      text-align: center;
    }

    .layout {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 320px;
      gap: 16px;
      align-items: start;
    }

    section, aside {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
    }

    label {
      display: block;
      margin-bottom: 8px;
      color: var(--muted);
      font-size: 13px;
      font-weight: 650;
    }

    textarea, input, select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 8px;
      background: #fff;
      color: var(--text);
      font: inherit;
      outline: none;
    }

    textarea:focus, input:focus, select:focus {
      border-color: var(--accent);
      box-shadow: 0 0 0 3px rgba(15, 118, 110, 0.12);
    }

    textarea {
      min-height: 180px;
      resize: vertical;
      padding: 14px;
      line-height: 1.5;
    }

    input, select {
      height: 42px;
      padding: 0 11px;
    }

    .field { margin-bottom: 14px; }

    .row {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }

    .checks {
      display: grid;
      gap: 10px;
      margin-top: 2px;
    }

    .check {
      display: flex;
      align-items: center;
      gap: 8px;
      color: var(--text);
      font-size: 14px;
    }

    .check input {
      width: 17px;
      height: 17px;
      margin: 0;
      accent-color: var(--accent);
    }

    button {
      width: 100%;
      height: 46px;
      border: 0;
      border-radius: 8px;
      background: var(--accent);
      color: white;
      font: inherit;
      font-weight: 750;
      cursor: pointer;
    }

    button:hover { background: var(--accent-dark); }
    button:disabled { cursor: wait; opacity: 0.68; }

    .answer {
      min-height: 180px;
      margin-top: 16px;
      padding: 16px;
      border-radius: 8px;
      background: var(--answer);
      border: 1px solid #cbe5df;
      white-space: pre-wrap;
      line-height: 1.55;
    }

    .error {
      color: var(--danger);
      background: #fff3f1;
      border-color: #ffd3ce;
    }

    .hint {
      margin: 10px 0 0;
      color: var(--muted);
      font-size: 12px;
      line-height: 1.45;
    }

    @media (max-width: 820px) {
      header { display: block; }
      .status { margin-top: 14px; text-align: left; }
      .layout { grid-template-columns: 1fr; }
      .row { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Local Coding AI</h1>
        <p class="subtitle">Isi pertanyaan, pilih model, lalu jalankan inferensi lokal di Mac.</p>
      </div>
      <div id="status" class="status">Siap</div>
    </header>

    <div class="layout">
      <section>
        <form id="askForm">
          <div class="field">
            <label for="prompt">Pertanyaan</label>
            <textarea id="prompt" name="prompt" placeholder="Tulis pertanyaan coding di sini..." required>Buatkan fungsi JavaScript untuk validasi email dan jelaskan singkat.</textarea>
          </div>
          <button id="submitBtn" type="submit">Kirim Pertanyaan</button>
        </form>

        <div id="answer" class="answer">Jawaban akan muncul di sini.</div>
      </section>

      <aside>
        <div class="field">
          <label for="modelId">Model Hugging Face atau path lokal</label>
          <input id="modelId" value="%DEFAULT_MODEL%">
          <p class="hint">Untuk Mac 16 GB, model MLX 4-bit ini lebih ringan untuk coding lokal.</p>
        </div>

        <div class="field">
          <label for="backend">Backend</label>
          <select id="backend">
            <option value="mlx_lm">MLX-LM untuk Mac</option>
            <option value="airllm">AirLLM</option>
          </select>
        </div>

        <div class="row">
          <div class="field">
            <label for="maxLength">Panjang input</label>
            <input id="maxLength" type="number" min="8" max="8192" value="256">
          </div>
          <div class="field">
            <label for="maxNewTokens">Token jawaban</label>
            <input id="maxNewTokens" type="number" min="1" max="1024" value="80">
          </div>
        </div>

        <div class="field">
          <label for="compression">Kompresi</label>
          <select id="compression">
            <option value="">Tanpa kompresi</option>
            <option value="4bit">4bit</option>
            <option value="8bit">8bit</option>
          </select>
        </div>

        <div class="field">
          <label for="hfToken">Hugging Face token</label>
          <input id="hfToken" type="password" autocomplete="off" placeholder="Opsional untuk gated model">
        </div>

        <div class="field">
          <label for="shardPath">Folder simpan layer</label>
          <input id="shardPath" placeholder="Opsional">
        </div>

        <div class="checks">
          <label class="check">
            <input id="deleteOriginal" type="checkbox">
            Hapus model asli setelah dipecah
          </label>
        </div>
      </aside>
    </div>
  </main>

  <script>
    const form = document.getElementById("askForm");
    const answer = document.getElementById("answer");
    const statusBox = document.getElementById("status");
    const submitBtn = document.getElementById("submitBtn");

    function setBusy(isBusy) {
      submitBtn.disabled = isBusy;
      submitBtn.textContent = isBusy ? "Memproses..." : "Kirim Pertanyaan";
      statusBox.textContent = isBusy ? "Model berjalan" : "Siap";
    }

    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      answer.classList.remove("error");
      answer.textContent = "Memuat model dan membuat jawaban. Proses pertama bisa lama...";
      setBusy(true);

      const payload = {
        prompt: document.getElementById("prompt").value,
        model_id: document.getElementById("modelId").value,
        max_length: Number(document.getElementById("maxLength").value),
        max_new_tokens: Number(document.getElementById("maxNewTokens").value),
        compression: document.getElementById("compression").value,
        backend: document.getElementById("backend").value,
        hf_token: document.getElementById("hfToken").value,
        layer_shards_saving_path: document.getElementById("shardPath").value,
        delete_original: document.getElementById("deleteOriginal").checked
      };

      try {
        const response = await fetch("/ask", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        });
        const data = await response.json();
        if (!response.ok || data.error) {
          throw new Error(data.error || "Gagal membuat jawaban.");
        }
        answer.textContent = data.answer || "(Jawaban kosong)";
      } catch (error) {
        answer.classList.add("error");
        answer.textContent = error.message;
      } finally {
        setBusy(false);
      }
    });
  </script>
</body>
</html>
""".replace("%DEFAULT_MODEL%", escape(DEFAULT_MODEL))


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def html_response(handler: BaseHTTPRequestHandler) -> None:
    body = HTML.encode("utf-8")
    handler.send_response(HTTPStatus.OK)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def load_airllm_model(options: dict[str, Any]):
    from airllm import AutoModel

    model_id = options["model_id"]
    kwargs: dict[str, Any] = {
        "delete_original": options["delete_original"],
    }

    if options["compression"]:
        kwargs["compression"] = options["compression"]
    if options["hf_token"]:
        kwargs["hf_token"] = options["hf_token"]
    if options["layer_shards_saving_path"]:
        kwargs["layer_shards_saving_path"] = options["layer_shards_saving_path"]

    cache_key = (
        model_id,
        kwargs.get("compression"),
        bool(kwargs.get("hf_token")),
        kwargs.get("layer_shards_saving_path"),
        kwargs.get("delete_original"),
        platform.system(),
    )

    with STATE.lock:
        if STATE.model is not None and STATE.cache_key == cache_key:
            return STATE.model

        STATE.model = AutoModel.from_pretrained(model_id, **kwargs)
        STATE.cache_key = cache_key
        return STATE.model


def load_mlx_lm_model(options: dict[str, Any]):
    from mlx_lm import load

    model_id = options["model_id"]
    cache_key = (
        "mlx_lm",
        model_id,
        platform.system(),
    )

    with STATE.lock:
        if STATE.model is not None and STATE.cache_key == cache_key:
            return STATE.model

        STATE.model = load(model_id)
        STATE.cache_key = cache_key
        return STATE.model


def generate_answer(options: dict[str, Any]) -> str:
    if options["backend"] == "mlx_lm":
        from mlx_lm import generate

        model, tokenizer = load_mlx_lm_model(options)
        prompt = options["prompt"]
        if hasattr(tokenizer, "apply_chat_template") and tokenizer.chat_template is not None:
            prompt = tokenizer.apply_chat_template(
                [{"role": "user", "content": prompt}],
                tokenize=False,
                add_generation_prompt=True,
            )

        return generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=options["max_new_tokens"],
            verbose=False,
        )

    model = load_airllm_model(options)
    prompt = options["prompt"]
    max_length = options["max_length"]
    max_new_tokens = options["max_new_tokens"]

    if sys.platform == "darwin":
        import mlx.core as mx

        input_tokens = model.tokenizer(
            [prompt],
            return_tensors="np",
            return_attention_mask=False,
            truncation=True,
            max_length=max_length,
            padding=False,
        )
        output = model.generate(
            mx.array(input_tokens["input_ids"]),
            max_new_tokens=max_new_tokens,
            use_cache=True,
            return_dict_in_generate=True,
        )
        return str(output)

    import torch

    input_tokens = model.tokenizer(
        [prompt],
        return_tensors="pt",
        return_attention_mask=False,
        truncation=True,
        max_length=max_length,
        padding=False,
    )
    input_ids = input_tokens["input_ids"]
    if torch.cuda.is_available():
        input_ids = input_ids.cuda()

    output = model.generate(
        input_ids,
        max_new_tokens=max_new_tokens,
        use_cache=True,
        return_dict_in_generate=True,
    )

    if isinstance(output, str):
        return output
    if hasattr(output, "sequences"):
        return model.tokenizer.decode(output.sequences[0], skip_special_tokens=True)
    return str(output)


def parse_options(raw: dict[str, Any]) -> dict[str, Any]:
    prompt = str(raw.get("prompt", "")).strip()
    model_id = str(raw.get("model_id", "")).strip() or DEFAULT_MODEL
    compression = str(raw.get("compression", "")).strip()
    backend = str(raw.get("backend", "mlx_lm")).strip()

    if not prompt:
        raise ValueError("Pertanyaan masih kosong.")
    if compression not in {"", "4bit", "8bit"}:
        raise ValueError("Pilihan kompresi tidak valid.")
    if backend not in {"mlx_lm", "airllm"}:
        raise ValueError("Backend tidak valid.")

    return {
        "prompt": prompt,
        "model_id": model_id,
        "backend": backend,
        "max_length": max(8, min(int(raw.get("max_length") or 256), 8192)),
        "max_new_tokens": max(1, min(int(raw.get("max_new_tokens") or 80), 1024)),
        "compression": compression,
        "hf_token": str(raw.get("hf_token", "")).strip(),
        "layer_shards_saving_path": str(raw.get("layer_shards_saving_path", "")).strip(),
        "delete_original": bool(raw.get("delete_original", False)),
    }


class AirLLMHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            html_response(self)
            return
        if path == "/health":
            json_response(self, HTTPStatus.OK, {"ok": True})
            return
        json_response(self, HTTPStatus.NOT_FOUND, {"error": "Halaman tidak ditemukan."})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/ask":
            json_response(self, HTTPStatus.NOT_FOUND, {"error": "Endpoint tidak ditemukan."})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(raw_body or "{}")
            options = parse_options(payload)
            answer = generate_answer(options)
            json_response(self, HTTPStatus.OK, {"answer": answer})
        except Exception as exc:
            traceback.print_exc()
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(exc)})


def main() -> None:
    host = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HOST
    port = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_PORT
    server = ThreadingHTTPServer((host, port), AirLLMHandler)
    print(f"AirLLM UI berjalan di http://{host}:{port}")
    print("Tekan Ctrl+C untuk berhenti.")
    server.serve_forever()


if __name__ == "__main__":
    main()
