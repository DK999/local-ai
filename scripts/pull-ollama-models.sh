#!/usr/bin/env bash
# Ollama Model Puller (idempotent) -- robust version
# - wartet auf Ollama-API
# - erkennt VRAM (NVIDIA/sysfs) -> wählt Q4/Q5 passend
# - akzeptiert benutzerdefinierte Liste via CODING_MODELS
# - fällt von -q5_K_M/-q4_K_M auf Basistag zurück, wenn Tag nicht existiert

set -euo pipefail

log()  { printf '%s %s\n' "[$(date +'%F %T')]" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

# ---------------------- Funktionen ----------------------

wait_for_ollama() {
  local host="${1}"
  log "⏳ Warte auf Ollama API unter ${host} ..."

  # 1) Try using the Ollama CLI (preferred; always present in the image)
  for _ in $(seq 1 120); do
    if OLLAMA_HOST="${host}" ollama list >/dev/null 2>&1; then
      log "✅ Ollama API erreichbar (per ollama CLI)."
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
        log "✅ Ollama API erreichbar (nach TCP-Fallback)."
        return 0
      fi
    fi
    sleep 1
  done

  fail "Ollama API nicht erreichbar unter ${host}"
}

detect_vram_mb() {
  # 0) Expliziter Hint (host-seitig gesetzt; gewinnt immer)
  if [[ -n "${INIT_VRAM_HINT_MB:-}" && "${INIT_VRAM_HINT_MB}" =~ ^[0-9]+$ ]]; then
    echo "${INIT_VRAM_HINT_MB}"
    return
  fi

  # 1) NVIDIA: Falls nvidia-smi im Container existiert (selten)
  if command -v nvidia-smi >/dev/null 2>&1; then
    local mb
    mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
    [[ -n "$mb" ]] && { echo "$mb"; return; }
  fi

  # 2) AMD (oder ggf. iGPU): sysfs (Bytes -> MiB)
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

  # 3) Fallback: konservativer Default mit Warnung
  #    (passend für viele 16 GB‑Setups; lässt Headroom für KV‑Cache)
  log "⚠ Konnte VRAM nicht automatisch ermitteln – verwende konservativen Default 16000 MB."
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
  local base="${tag%%-q*}"
  if [[ "${base}" != "${tag}" ]]; then
    log "   … Fallback ohne Quant: ${base}"
    ollama pull "${base}" || return 1
  else
    return 1
  fi
}

print_list() {
  local -a arr=("$@")
  for m in "${arr[@]}"; do printf '  - %s\n' "$m"; done
}

# ---------------------- Hauptteil ----------------------

log "▶ Ollama Model Puller – Start"

# Standard-Host innerhalb Compose (per ENV überschreibbar)
: "${OLLAMA_HOST:=http://ollama:11434}"

# Warten bis API erreichbar
wait_for_ollama "${OLLAMA_HOST}"

# Benutzerdefinierte Liste?
if [[ -n "${CODING_MODELS:-}" ]]; then
  # Komma/Space-getrennt akzeptieren
  IFS=', ' read -r -a DEFAULT_MODELS <<< "${CODING_MODELS}"
  log "🧾 Benutzerdefinierte Modellauswahl (CODING_MODELS):"
  print_list "${DEFAULT_MODELS[@]}"
else
  # Adaptive Defaults für ~16–24 GB
  VRAM_MB="$(detect_vram_mb)"
  log "🧠 Erkannte VRAM: ${VRAM_MB} MB"

  if [[ "${VRAM_MB}" -ge 18000 ]]; then
    # Mehr Qualität bei ≥18 GB: Q5_K_M
    DEFAULT_MODELS=(
      "qwen2.5-coder:14b-instruct-q5_K_M" # Chat-Model for Open-WebUI
      "deepseek-coder-v2:latest" # or :lite to pin Q4_0, Chat-Model for Open-WebUI
      "deepseek-r1:32b-q3_K_M" # Chat model optimized for coding
      "qwen3-embedding:0.6b" # Embedding model - Convert text into numerical vectors so you can compare meaning, not just words.
      "dengcao/qwen3-reranker-0.6b:q8_0" # Reranker modek - Improve search or RAG results by scoring the relevance of (query, document) pairs with higher accuracy than embeddings.
      "qwen2.5-coder:1.5b-base" # Autocomplete model - Predict the next tokens for fast inline typing completion.
    )
  else
    # Safer‑Headroom für 16 GB: Q4_K_M
    DEFAULT_MODELS=(
#      "qwen2.5-coder:14b-instruct-q4_K_M" # Chat-Model for Open-WebUI
#      "deepseek-coder-v2:latest" # or :lite to pin Q4_0, Chat-Model for Open-WebUI
      "deepseek-r1:14b-q8_0" # Chat model optimized for coding
      "qwen3-embedding:0.6b" # Embedding model - Convert text into numerical vectors so you can compare meaning, not just words.
      "dengcao/qwen3-reranker-0.6b:q8_0" # Reranker modek - Improve search or RAG results by scoring the relevance of (query, document) pairs with higher accuracy than embeddings.
      "qwen2.5-coder:1.5b-base" # Autocomplete model - Predict the next tokens for fast inline typing completion.
    )
  fi

  log "📦 Zielliste:"
  print_list "${DEFAULT_MODELS[@]}"
fi

# OLLAMA_HOST für CLI exportieren
export OLLAMA_HOST="${OLLAMA_HOST}"

# Modelle idempotent ziehen
for model in "${DEFAULT_MODELS[@]}"; do
  if already_installed "${OLLAMA_HOST}" "${model}"; then
    log "✔ Bereits vorhanden: ${model}"
    continue
  fi
  if ! pull_with_fallback "${model}"; then
    log "⚠ Konnte ${model} nicht ziehen. Weiter mit nächstem."
  fi
done

log "🏁 Fertig. Installierte Modelle:"
ollama list || true
