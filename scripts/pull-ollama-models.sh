#!/usr/bin/env bash
# Ollama Model Puller (idempotent) -- robust version
# - waits for Ollama API
# - detects VRAM (NVIDIA/sysfs) -> picks matching Q4/Q5
# - accepts custom list via CODING_MODELS
# - falls back from -q5_K_M/-q4_K_M to base tag when tag does not exist

set -euo pipefail

log()  { printf '%s %s\n' "[$(date +'%F %T')]" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

# ---------------------- Functions ----------------------

wait_for_ollama() {
  local host="${1}"
  log "⏳ Waiting for Ollama API at ${host} ..."

  # 1) Try using the Ollama CLI (preferred; always present in the image)
  for _ in $(seq 1 120); do
    if OLLAMA_HOST="${host}" ollama list >/dev/null 2>&1; then
      log "✅ Ollama API reachable (via ollama CLI)."
      return 0
    fi
    sleep 2
  done

  # 2) Optional fallback: pure Bash TCP check (no curl/wget needed)
  #    Only used if the CLI path above didn’t succeed within the time window.
  #    This checks that the port is open; it doesn't guarantee the HTTP endpoint.
  local h port
  h="${host##*//}"       # strip scheme
  h="${h%%/*}"           # strip path (if any)
  port="${h##*:}"; h="${h%%:*}"
  [[ -z "${port}" || "${port}" = "${h}" ]] && port="80"

  log "🧪 Fallback: Port-Check via /dev/tcp for ${h}:${port}"
  for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/${h}/${port}") 2>/dev/null; then
      exec 3>&- 3<&-
      # One last CLI probe to be sure
      if OLLAMA_HOST="${host}" ollama list >/dev/null 2>&1; then
        log "✅ Ollama API reachable (after TCP fallback)."
        return 0
      fi
    fi
    sleep 1
  done

  fail "Ollama API not reachable at ${host}"
}

detect_vram_mb() {
  # 0) Explicit hint (set on host side; always wins)
  if [[ -n "${INIT_VRAM_HINT_MB:-}" && "${INIT_VRAM_HINT_MB}" =~ ^[0-9]+$ ]]; then
    echo "${INIT_VRAM_HINT_MB}"
    return
  fi

  # 1) NVIDIA: if nvidia-smi exists in container (rare)
  if command -v nvidia-smi >/dev/null 2>&1; then
    local mb
    mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
    [[ -n "$mb" ]] && { echo "$mb"; return; }
  fi

  # 2) AMD (or possibly iGPU): sysfs (Bytes -> MiB)
  for f in /sys/class/drm/card*/device/mem_info_vram_total /sys/class/drm/card*/device/vram_total; do
    if [[ -r "$f" ]]; then
      local bytes
      bytes=$(cat "$f" 2>/dev/null | head -n1 || true)
      if [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo $(( bytes / 1024 / 1024 ))
        return
      fi
    fi
  done

  # 3) Fallback: conservative default with warning
  #    (fits many 16 GB setups; leaves headroom for KV cache)
  log "⚠ Could not detect VRAM automatically - using conservative default 16000 MB."
  echo "16000"
}

already_installed() {
  local host="$1" tag="$2"
  local base="${tag%%:*}"
  if OLLAMA_HOST="${host}" ollama list 2>/dev/null | grep -q "^${base}$"; then
    return 0
  fi
  return 1
}

pull_with_fallback() {
  local tag="$1"
  log "→ Pull: ${tag}"
  if ollama pull "${tag}"; then
    return 0
  fi
  # Fallback: Quant‑Suffix entfernen (z. B. -q5_K_M / -q4_K_M)
  # Fallback: remove quant suffix (e.g. -q5_K_M / -q4_K_M)
  local base="${tag%%-q*}"
  if [[ "${base}" != "${tag}" ]]; then
    log "   ... Fallback without quant: ${base}"
    ollama pull "${base}" || return 1
  else
    return 1
  fi
}

print_list() {
  local -a arr=("$@")
  for m in "${arr[@]}"; do printf '  - %s\n' "$m"; done
}

# ---------------------- Main section ----------------------

log "▶ Ollama Model Puller – Start"

# Default host inside Compose (overridable via ENV)
: "${OLLAMA_HOST:=http://ollama:11434}"

# Wait until API is reachable
wait_for_ollama "${OLLAMA_HOST}"

# Custom list?
if [[ -n "${CODING_MODELS:-}" ]]; then
  # Accept comma/space-separated values
  IFS=', ' read -r -a DEFAULT_MODELS <<< "${CODING_MODELS}"
  log "🧾 Custom model selection (CODING_MODELS):"
  print_list "${DEFAULT_MODELS[@]}"
else
  # Adaptive defaults for ~16–24 GB
  VRAM_MB="$(detect_vram_mb)"
  log "🧠 Detected VRAM: ${VRAM_MB} MB"

  if [[ "${VRAM_MB}" -ge 18000 ]]; then
    # Higher quality at >=18 GB: Q5_K_M
    DEFAULT_MODELS=(
      "qwen2.5-coder:14b-instruct-q5_K_M" # Chat-Model for Open-WebUI
      "deepseek-coder-v2:latest" # or :lite to pin Q4_0, Chat-Model for Open-WebUI
      "deepseek-r1:32b-q3_K_M" # Chat model optimized for coding
      "qwen3-embedding:0.6b" # Embedding model - Convert text into numerical vectors so you can compare meaning, not just words.
      "dengcao/qwen3-reranker-0.6b:q8_0" # Reranker modek - Improve search or RAG results by scoring the relevance of (query, document) pairs with higher accuracy than embeddings.
      "qwen2.5-coder:1.5b-base" # Autocomplete model - Predict the next tokens for fast inline typing completion.
    )
  else
    # Safer headroom for 16 GB: Q4_K_M
    DEFAULT_MODELS=(
#      "qwen2.5-coder:14b-instruct-q4_K_M" # Chat-Model for Open-WebUI
#      "deepseek-coder-v2:latest" # or :lite to pin Q4_0, Chat-Model for Open-WebUI
      "deepseek-r1:14b-q8_0" # Chat model optimized for coding
      "qwen3-embedding:0.6b" # Embedding model - Convert text into numerical vectors so you can compare meaning, not just words.
      "dengcao/qwen3-reranker-0.6b:q8_0" # Reranker modek - Improve search or RAG results by scoring the relevance of (query, document) pairs with higher accuracy than embeddings.
      "qwen2.5-coder:1.5b-base" # Autocomplete model - Predict the next tokens for fast inline typing completion.
    )
  fi

  log "📦 Target list:"
  print_list "${DEFAULT_MODELS[@]}"
fi

# Export OLLAMA_HOST for CLI
export OLLAMA_HOST="${OLLAMA_HOST}"

# Pull models idempotently
for model in "${DEFAULT_MODELS[@]}"; do
  if already_installed "${OLLAMA_HOST}" "${model}"; then
    log "✔ Already installed: ${model}"
    continue
  fi
  if ! pull_with_fallback "${model}"; then
    log "⚠ Could not pull ${model}. Continuing with next one."
  fi
done

log "🏁 Done. Installed models:"
ollama list || true
