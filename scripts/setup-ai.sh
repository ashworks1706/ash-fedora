#!/usr/bin/env bash
# Local AI server: llama.cpp (CUDA) behind llama-swap, one OpenAI-compatible endpoint
# at http://127.0.0.1:8100/v1 for chat, projects and Hermes. Safe to rerun.
#
#   ./scripts/setup-ai.sh            build + default models
#   ./scripts/setup-ai.sh --cpu      build without CUDA (no NVIDIA GPU)
#
# Needs: cmake, ninja-build, git, gcc15-c++ (CUDA 13 host compiler), CUDA toolkit
# (nvcc), jq, curl. Run scripts/install.sh first (config + systemd unit).
set -euo pipefail

LLM="$HOME/.local/share/llm"
SRC="$HOME/.local/src/llama.cpp"
MODELS="$LLM/models"
step() { printf '\n\e[1;36m==> %s\e[0m\n' "$*"; }
cuda=1; [[ "${1:-}" == "--cpu" ]] && cuda=0

# fetch REPO FILE [SAVE_AS]: download from Hugging Face, verified against its sha256
fetch() {
  local repo="$1" file="$2" out="${3:-$2}"
  [[ -f "$MODELS/$out" ]] && { echo "  have $out"; return; }
  local sha
  sha=$(curl -fsSL "https://huggingface.co/api/models/$repo/tree/main" | jq -r --arg f "$file" '.[]|select(.path==$f)|.lfs.oid')
  curl -fL --progress-bar -o "$MODELS/$out.part" "https://huggingface.co/$repo/resolve/main/$file"
  echo "$sha  $MODELS/$out.part" | sha256sum -c - && mv "$MODELS/$out.part" "$MODELS/$out"
}

step "1. llama.cpp (build from source; Fedora's package is too old for Qwen 3.5)"
if [[ ! -x "$LLM/llama.cpp/llama-server" ]]; then
  [[ -d "$SRC" ]] || git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$SRC"
  flags=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF)
  if [[ $cuda -eq 1 ]]; then
    export PATH=/usr/local/cuda/bin:$PATH
    # CUDA 13 rejects GCC 16 (Fedora 44's default); gcc15 is supported.
    flags+=(-DGGML_CUDA=ON -DCMAKE_CUDA_HOST_COMPILER=/usr/bin/g++-15)
    arch=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d .)
    [[ -n "$arch" ]] && flags+=(-DCMAKE_CUDA_ARCHITECTURES="$arch")   # build only for this GPU
  fi
  cmake -S "$SRC" -B "$SRC/build" "${flags[@]}"
  nice -n 10 cmake --build "$SRC/build" --target llama-server llama-cli llama-bench -j "$(nproc)"
  mkdir -p "$LLM/llama.cpp" && cp -a "$SRC/build/bin/." "$LLM/llama.cpp/"
fi

step "2. llama-swap (checksum-verified release)"
if [[ ! -x "$LLM/bin/llama-swap" ]]; then
  rel=$(curl -fsSL https://api.github.com/repos/mostlygeek/llama-swap/releases/latest)
  asset=$(jq -c '.assets[] | select(.name|test("linux_amd64.tar.gz$"))' <<<"$rel")
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/ls.tgz" "$(jq -r .browser_download_url <<<"$asset")"
  echo "$(jq -r '.digest | sub("^sha256:";"")' <<<"$asset")  $tmp/ls.tgz" | sha256sum -c -
  mkdir -p "$LLM/bin" && tar xzf "$tmp/ls.tgz" -C "$LLM/bin" llama-swap && rm -rf "$tmp"
fi

step "3. Models (verified against Hugging Face checksums)"
mkdir -p "$MODELS"
fetch unsloth/Qwen3.5-4B-GGUF Qwen3.5-4B-Q4_K_M.gguf                       # chat, tools, vision
fetch unsloth/Qwen3.5-4B-GGUF mmproj-F16.gguf Qwen3.5-4B-mmproj-F16.gguf    # its vision projector
fetch Qwen/Qwen3-Embedding-0.6B-GGUF Qwen3-Embedding-0.6B-Q8_0.gguf         # 1024-dim embeddings
fetch nomic-ai/nomic-embed-text-v1.5-GGUF nomic-embed-text-v1.5.f16.gguf nomic-embed-text-v1.5.gguf
echo "  optional (listed in llama-swap.yaml, add the files to use them):"
echo "    $MODELS/qwen2.5-7b-instruct.gguf, $MODELS/qwen2.5-coder-1.5b-base.gguf"

step "4. API key and service"
mkdir -p "$HOME/.config/llm"
if [[ ! -f "$HOME/.config/llm/env" ]]; then
  (umask 077; printf 'LLM_API_KEY=sk-local-%s\n' "$(head -c 24 /dev/urandom | base64 | tr -d '/+=')" > "$HOME/.config/llm/env")
fi
set -a; . "$HOME/.config/llm/env"; set +a
"$LLM/bin/llama-swap" -config "$HOME/.config/llm/llama-swap.yaml" -validate
systemctl --user daemon-reload
systemctl --user enable --now llama-swap.service
command -v tailscale >/dev/null && tailscale serve --bg --https=8100 http://127.0.0.1:8100 >/dev/null || true

echo
echo "Ready: http://127.0.0.1:8100/v1   (key: grep LLM_API_KEY ~/.config/llm/env)"
echo "Chat UI: http://127.0.0.1:8100/upstream/qwen3.5-4b/  (login: any name + the key)"
echo "See docs/AI.md to point projects and Hermes at it."
