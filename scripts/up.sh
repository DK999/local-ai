#!/usr/bin/env bash
set -euo pipefail

# ==========================
# Self-repair Orchestrator
#  - selects GPU profile (NVIDIA/AMD/Vulkan/CPU)
#  - starts only the profile's Ollama service
#  - waits robustly for HEALTHY (retry/restart)
#  - runs model pull as one-shot (idempotent)
#  - starts Open-WebUI afterwards
#  - Auto-Fallback (z. B. AMD ohne /dev/kfd -> Vulkan -> CPU)
# ==========================

# ---------- Configuration ----------
PROJECT="${PROJECT:-ollama-stack}"
COMPOSE_FILE="${COMPOSE_FILE:-ai.yml}"

# Timeouts / interval (adjust as needed)
WAIT_HEALTH_SECS="${WAIT_HEALTH_SECS:-360}"     # Max wait time for HEALTHY
SLEEP_HEALTH_SECS="${SLEEP_HEALTH_SECS:-3}"     # Poll interval
RESTART_ON_UNHEALTHY="${RESTART_ON_UNHEALTHY:-1}" # 1=restart once

HOST_VRAM_MB="16000"

# ---------- Helper functions ----------
is_cmd() { command -v "$1" >/dev/null 2>&1; }

die() { echo "❌ $*" >&2; exit 1; }

msg() { echo -e "$*"; }


detect_profile_and_vram() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    local mb
    mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)"
    printf '%s %s\n' "nvidia" "${mb}"
    return
  fi
  if [[ -e /dev/kfd ]]; then
    printf '%s %s\n' "amd" ""
    return
  fi
  if ls /dev/dri/renderD* >/dev/null 2>&1; then
    printf '%s %s\n' "vulkan" ""
    return
  fi
  printf '%s %s\n' "cpu" ""
}

svc_names_for_profile() {
  local profile="$1"
  case "$profile" in
    nvidia)
      echo "ollama-nvidia ollama-init-nvidia open-webui-nvidia" ;;
    amd)
      echo "ollama-amd ollama-init-amd open-webui-amd" ;;
    vulkan)
      echo "ollama-vulkan ollama-init-vulkan open-webui-vulkan" ;;
    cpu)
      echo "ollama-cpu ollama-init-cpu open-webui-cpu" ;;
    *)
      die "Unknown profile: $profile"
      ;;
  esac
}

dc() { 
  # Dynamically read GIDs from the host
  VIDEO_GID=$(getent group video | cut -d: -f3 || echo "")
  RENDER_GID=$(getent group render | cut -d: -f3 || echo "")

  # Pass through to Docker Compose via environment variables
  VIDEO_GID="${VIDEO_GID}" \
  RENDER_GID="${RENDER_GID}" \
  docker compose --project-name "$PROJECT" -f "$COMPOSE_FILE" --profile "$PROFILE" "$@"
}

find_container_by_service() {
  # Find the container for a Compose service (regardless of container_name)
  local svc="$1"
  docker ps -a \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=$svc" \
    --format '{{.ID}} {{.Names}}' | head -n1
}

health_status() {
  local container_id="$1"
  # Returns "healthy", "unhealthy", or "none" (if no healthcheck)
  local st
  st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")
  echo "$st"
}

wait_for_healthy_or_timeout() {
  local svc="$1"
  local deadline=$(( $(date +%s) + WAIT_HEALTH_SECS ))

  # Find container ID/name
  local cid cname
  read -r cid cname < <(find_container_by_service "$svc")
  [[ -n "${cid:-}" ]] || die "No container found for service '$svc'."

  while true; do
    local now
    now=$(date +%s)
    local left=$(( deadline - now ))
    local st
    st=$(health_status "$cid")

    if [[ "$st" == "healthy" ]]; then
      msg "✅ Service '$svc' is HEALTHY (Container: $cname)"
      return 0
    fi

    if (( left <= 0 )); then
      msg "⏱️  Timeout: Service '$svc' is '$st' after ${WAIT_HEALTH_SECS}s"
      return 1
    fi

    sleep "$SLEEP_HEALTH_SECS"
  done
}

print_diag() {
  local svc="$1"
  local cid cname
  read -r cid cname < <(find_container_by_service "$svc")
  [[ -n "${cid:-}" ]] || { msg "ℹ️  No container data for $svc"; return; }

  msg "\n----- DIAGNOSTICS: $svc ($cname) -----"
  docker inspect -f '{{json .State.Health}}' "$cid" 2>/dev/null || true
  echo
  docker logs --tail=400 "$cid" 2>&1 || true
  msg "----- END DIAGNOSTICS -----\n"
}

try_restart_once() {
  local svc="$1"
  if [[ "${RESTART_ON_UNHEALTHY}" != "1" ]]; then
    return 1
  fi
  local cid cname
  read -r cid cname < <(find_container_by_service "$svc")
  [[ -n "${cid:-}" ]] || return 1

  msg "🔁 Unhealthy -> one-time restart of '$svc' (Container: $cname) ..."
  docker restart "$cid" >/dev/null
  sleep 3
  wait_for_healthy_or_timeout "$svc"
}

switch_profile() {
  local new="$1"
  msg "🔀 Automatically switching to profile: $new"
  PROFILE="$new"
}

bring_up_ollama() {
  local svc="$1"
  msg "▶ Starting Ollama service: $svc (Profile: $PROFILE)"
  dc up -d "$svc"
  if wait_for_healthy_or_timeout "$svc"; then
    return 0
  fi
  print_diag "$svc"

  # If unhealthy -> one-time restart attempt
  if try_restart_once "$svc"; then
    return 0
  fi
  return 1
}

run_init_once() {
  local init_svc="$1"
  msg "📦 Starting pull init (one-shot): $init_svc"
  msg "Detected VRAM: ${HOST_VRAM_MB}"
  # One-shot so it stays idempotent each run and leaves no zombie containers
  if ! dc run -e INIT_VRAM_HINT_MB="${HOST_VRAM_MB}" --rm "$init_svc"; then
    msg "⚠️  Pull init reported an error. Logs follow:"
    # Capture the latest init container (if present)
    docker ps -a --filter "name=${PROJECT}-.*${init_svc}" --format '{{.ID}} {{.Names}}' | head -n1 | while read -r icid iname; do
      [[ -n "${icid:-}" ]] && docker logs --tail=200 "$icid" || true
    done
    return 1
  fi
  msg "✅ Models loaded (if not already present)."
}

start_webui() {
  local webui_svc="$1"
  msg "💻 Starting Open‑WebUI: $webui_svc"
  dc up -d "$webui_svc"
  msg "🔗 Open‑WebUI: http://localhost:${OPEN_WEBUI_PORT:-3000}"
}

# ---------- Main flow ----------
# 1) Profile selection (or set via PROFILE env)

read -r PROFILE HOST_VRAM_MB < <(detect_profile_and_vram)
msg "▶ Detected profile: ${PROFILE}"
msg "Detected VRAM (host): ${HOST_VRAM_MB:-<empty>}"

read -r OLLAMA_SVC INIT_SVC WEBUI_SVC < <(svc_names_for_profile "$PROFILE")

# 2) Try the requested profile
if bring_up_ollama "$OLLAMA_SVC"; then
  run_init_once "$INIT_SVC" || true
  start_webui "$WEBUI_SVC"
  msg "🎉 Success: profile '$PROFILE' is running."
  exit 0
fi

# 3) Auto fallbacks (self-repair)
case "$PROFILE" in
  amd)
    # Most common reason: /dev/kfd missing -> try Vulkan
    if [[ ! -e /dev/kfd ]]; then
      switch_profile "vulkan"
      read -r OLLAMA_SVC INIT_SVC WEBUI_SVC < <(svc_names_for_profile "$PROFILE")
      if bring_up_ollama "$OLLAMA_SVC"; then
        run_init_once "$INIT_SVC" || true
        start_webui "$WEBUI_SVC"
        msg "🎉 Success: fallback to Vulkan."
        exit 0
      fi
    fi
    ;;&
  nvidia|amd|vulkan)
    # Next fallback: CPU
    switch_profile "cpu"
    read -r OLLAMA_SVC INIT_SVC WEBUI_SVC < <(svc_names_for_profile "$PROFILE")
    if bring_up_ollama "$OLLAMA_SVC"; then
      run_init_once "$INIT_SVC" || true
      start_webui "$WEBUI_SVC"
      msg "🎉 Success: fallback to CPU."
      exit 0
    fi
    ;;
esac

die "Could not find a working path. See diagnostics above."
