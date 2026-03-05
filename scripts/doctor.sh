#!/usr/bin/env bash
set -euo pipefail

echo "== GPU / Runtime Diagnostics =="

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[NVIDIA] Host nvidia-smi:"
  nvidia-smi || true
else
  echo "[NVIDIA] nvidia-smi not found."
fi

echo
echo "[Docker] Runtimes:"
docker info | sed -n '/Runtimes/,/Default/p' || true

echo
echo "[Devices] /dev/kfd: $( [[ -e /dev/kfd ]] && echo present || echo missing )"
echo "[Devices] /dev/dri :"
ls -l /dev/dri/* 2>/dev/null || echo "no /dev/dri/*"

echo
echo "[Compose] Projects with ollama:"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | grep -i ollama || true

echo
echo "== Quick Vulkan Test =="
if command -v vulkaninfo >/dev/null 2>&1; then
  vulkaninfo | head -n 20 || true
else
  echo "vulkaninfo not installed (optional)."
fi
``
