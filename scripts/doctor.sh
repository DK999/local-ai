#!/usr/bin/env bash
set -euo pipefail

echo "== GPU / Runtime Diagnose =="

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[NVIDIA] Host nvidia-smi:"
  nvidia-smi || true
else
  echo "[NVIDIA] nvidia-smi nicht gefunden."
fi

echo
echo "[Docker] Runtimes:"
docker info | sed -n '/Runtimes/,/Default/p' || true

echo
echo "[Devices] /dev/kfd: $( [[ -e /dev/kfd ]] && echo present || echo missing )"
echo "[Devices] /dev/dri :"
ls -l /dev/dri/* 2>/dev/null || echo "kein /dev/dri/*"

echo
echo "[Compose] Projekte mit ollama:"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -i ollama || true

echo
echo "== Quick Vulkan Test =="
if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo | head -n 20 || true
else
  echo "vulkaninfo nicht installiert (optional)."
fi
``
