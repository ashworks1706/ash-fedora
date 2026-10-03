# Local AI server

One OpenAI-compatible endpoint for every local model, shared by chat, your projects
and Hermes:

```
http://127.0.0.1:8100/v1              on this machine
https://<host>.ts.net:8100/v1         from your other Tailscale devices
Authorization: Bearer $LLM_API_KEY    grep LLM_API_KEY ~/.config/llm/env
```

**Setup:** `./scripts/install.sh` (config + unit), then `./scripts/setup-ai.sh` (build
llama.cpp with CUDA, download llama-swap and the models, start the service).

## How it works

```
 your projects ─┐                      ┌─ llama-server: Qwen 3.5 4B (chat, tools, vision)  GPU
 Hermes ────────┼──► llama-swap :8100 ─┼─ llama-server: Qwen3-Embedding 0.6B (1024-d)    CPU
 chat UI ───────┘   (picks by model,   └─ llama-server: nomic-embed-text v1.5 (768-d)     CPU
                     aliases, unloads)
```

- [**llama-swap**](https://github.com/mostlygeek/llama-swap) starts the `llama-server`
  for whichever model a request names, swaps chat models in and out of the GPU, and
  unloads them after 10 minutes idle (so the GPU is free for training).
- **llama.cpp** is built from source with CUDA (`setup-ai.sh`); Fedora's package is too
  old for Qwen 3.5.
- Config: [`config/llm/llama-swap.yaml`](../config/llm/llama-swap.yaml). Models live in
  `~/.local/share/llm/models/`.

## Models

| Model id | Also answers to | Use | Where |
|---|---|---|---|
| `qwen3.5-4b` | `qwen3.5:4b`, `qwen3-vl:4b`, `Qwen/Qwen3-4B-GGUF:Q4_K_M`, `qwen`, `default` | chat, tool calling, vision; 2 parallel slots × 64K context; ~50 tok/s | GPU |
| `qwen3-embedding-0.6b` | `Qwen/Qwen3-Embedding-0.6B-GGUF:Q8_0`, `qwen3-embedding`, `embed` | 1024-dim embeddings | CPU |
| `nomic-embed-text` | `nomic-embed-text:latest` | 768-dim embeddings | CPU |
| `qwen2.5-7b-instruct` | `qwen2.5:7b-instruct` | optional older 7B (32K context) | GPU |
| `qwen2.5-coder-1.5b-base` | `qwen2.5-coder:1.5b-base` | optional code completion | GPU |

The aliases are the names projects and Ollama already used, so switching a project over
only changes its base URL and key.

**6 GB VRAM budget:** Qwen 3.5 4B uses ~5.6 GB with 128K total context (8-bit KV cache;
the vision projector runs on the CPU). Embeddings stay on the CPU so they never compete.

## Chat

llama.cpp's built-in chat UI, served through llama-swap:

- `https://<host>.ts.net:8100/upstream/qwen3.5-4b/` — chat (Markdown, images, branching)
- `https://<host>.ts.net:8100/ui/` — llama-swap: loaded models, logs, activity

The browser asks for a login: any user name, the API key as password. The dashboard's
**Local AI** section links both and can unload all models.

## Dashboard

The dashboard's **Local AI** section shows live generation and prompt tokens/s (from
llama-server's `--metrics` counters plus in-progress slot progress), the loaded model
(file, modalities, slots × context, average speeds, tokens served), NVIDIA load/VRAM/
temperature/power, and Load / Unload / Logs / Chat controls.

## GPU utilization (RTX 4050 Laptop, measured)

| | |
|---|---|
| Prompt processing (512–2048 tokens) | ~2,400 tok/s |
| Generation, one stream | ~57 tok/s |
| Generation, two parallel streams | ~100 tok/s combined |
| During generation | 99–100% GPU, 100% memory controller, max memory clock, 84–90 W |

Generation is memory-bandwidth bound (192 GB/s ÷ 2.5 GB of weights ≈ 75 tok/s
ceiling), so ~57 tok/s is near the hardware limit; use the Performance power profile
on AC for full power. llama-swap's own GPU monitor is **disabled** in the config: it
runs `nvidia-smi` every 15 s, which keeps the dGPU from ever runtime-suspending.

## Pointing projects at it

| Project | Settings |
|---|---|
| sparkyai | `SPARKY_MODEL__BASE_URL`, `SPARKY_SUMMARY__BASE_URL`, `SPARKY_EMBEDDING__BASE_URL` = `http://127.0.0.1:8100/v1`; the matching `__API_KEY`s = the key. Model names in `sparky.toml` already match aliases. Don't start the compose `model` profile. |
| zipy | `ZIPY_AGENT__LLM__BASE_URL`, `ZIPY_COLLECT__BASE_URL` = `http://127.0.0.1:8100/v1`; `…__API_KEY` = the key |
| piramid | `startup.embedding: {provider: openai, model: nomic-embed-text, base_url: http://127.0.0.1:8100/v1}`; `OPENAI_API_KEY` = the key. Don't start its compose `ollama` profile. |
| loupe (evals) | Inspect model base URL `http://127.0.0.1:8100/v1`, API key = the key |
| anything else | `OPENAI_BASE_URL=http://127.0.0.1:8100/v1`, `OPENAI_API_KEY=<key>` |

Keep one embedding model per vector index: sparky's index is 1024-dim (Qwen3-Embedding),
nomic is 768-dim.

## Hermes

In `~/.hermes/config.yaml` the local fallback, vision and the `qwen` / `qwen-text`
aliases use `base_url: http://127.0.0.1:8100/v1`, with the key supplied by a
`custom_providers` entry named `llama-swap` (Hermes matches keys by base URL).
Hermes requires at least 64K context, which is why `qwen3.5-4b` runs 64K per slot.
Test: `hermes -m qwen -z "say hi"`.

## Training on the GPU

Chat models unload after 10 minutes idle. To free the GPU right away: **Unload all** on
the dashboard, or `curl -H "Authorization: Bearer $LLM_API_KEY" http://127.0.0.1:8100/unload`.
To keep it off: stop **Model server** on the dashboard (`systemctl --user stop llama-swap`).

## Adding a model

Put the `.gguf` in `~/.local/share/llm/models/` and add an entry to
`~/.config/llm/llama-swap.yaml` (it reloads on save). Ollama's own model files often
won't load in llama.cpp (Ollama-specific metadata); use GGUFs from Hugging Face.
