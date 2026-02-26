#!/usr/bin/env bash
set -euo pipefail

# Unified installer for GPU prerequisites (Ubuntu + Arch) for NVIDIA & AMD
# - NVIDIA: installs driver pre-reqs (where possible) + NVIDIA Container Toolkit, configures Docker runtime
# - AMD (Ubuntu): installs ROCm stack (kernel + userspace) and sets video/render groups
# - AMD (Arch): best-effort userspace + warning (ROCm is not officially supported on Arch)
# - Vulkan fallback: installs Vulkan userspace (Mesa) for non-ROCm AMD / Intel as a safety net
#
# Notes:
#   * Docker must be installed separately (script warns if missing).
#   * Reboot after installation for kernel modules & group membership to take effect.

# ---- Helpers -----------------------------------------------------------------

is_cmd() { command -v "$1" >/dev/null 2>&1; }

need_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "→ Using sudo for privileged operations..."
    SUDO="sudo"
  else
    SUDO=""
  fi
}

detect_pkg_mgr() {
  if is_cmd apt; then
    PKG="apt"
  elif is_cmd pacman; then
    PKG="pacman"
  else
    echo "❌ Unsupported system: need apt (Ubuntu/Debian) or pacman (Arch)."
    exit 1
  fi
}

detect_os_release() {
  OS_ID=""; OS_CODENAME=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"; OS_CODENAME="${VERSION_CODENAME:-}"
  fi
}

detect_gpu_vendor() {
  # Prefer explicit utilities
  if is_cmd nvidia-smi; then
    GPU_VENDOR="nvidia"; return
  fi
  if [[ -e /dev/kfd ]]; then
    GPU_VENDOR="amd"; return
  fi
  # Fallback to lspci
  if is_cmd lspci; then
    if lspci | grep -Eq "NVIDIA"; then GPU_VENDOR="nvidia"; return; fi
    if lspci | grep -Eq "AMD|ATI"; then GPU_VENDOR="amd"; return; fi
  fi
  GPU_VENDOR="unknown"
}

ensure_docker_warning() {
  if ! is_cmd docker; then
    echo "⚠️  Docker is not installed. Please install Docker before using GPU in containers."
    echo "   - Ubuntu: https://docs.docker.com/engine/install/ubuntu/"
    echo "   - Arch:   sudo pacman -S docker"
    echo "   After install: sudo systemctl enable --now docker"
    echo
  fi
}

# ---- NVIDIA (apt) ------------------------------------------------------------

install_nvidia_apt() {
  echo "===> NVIDIA (Ubuntu/Debian): Installing Container Toolkit and configuring Docker"
  $SUDO apt update
  $SUDO apt install -y curl gnupg ca-certificates

  # Add NVIDIA Container Toolkit repo (official instructions)
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | $SUDO gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

  $SUDO apt update
  $SUDO apt install -y nvidia-container-toolkit

  # Configure Docker runtime
  $SUDO nvidia-ctk runtime configure --runtime=docker || true
  $SUDO systemctl restart docker || true

  echo "✅ NVIDIA Container Toolkit installed and Docker runtime configured."
  echo "ℹ️  Ensure a suitable NVIDIA driver (>= 531) is installed and reboot if you just installed it."
}

# ---- NVIDIA (pacman) ---------------------------------------------------------

install_nvidia_pacman() {
  echo "===> NVIDIA (Arch): Installing drivers, utils, and Container Toolkit"
  $SUDO pacman -Sy --noconfirm nvidia nvidia-utils cuda nvidia-container-toolkit

  # Configure Docker runtime
  $SUDO nvidia-ctk runtime configure --runtime=docker || true
  $SUDO systemctl restart docker || true

  echo "✅ NVIDIA driver/utils/toolkit installed. Reboot recommended."
}

# ---- AMD ROCm (apt/Ubuntu) ---------------------------------------------------

install_amd_rocm_apt() {
  echo "===> AMD ROCm (Ubuntu): Installing ROCm kernel + userspace"

  # Add AMD ROCm repo key (ROCm stack)
  if ! is_cmd wget; then $SUDO apt update && $SUDO apt install -y wget; fi
  wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key | $SUDO apt-key add - >/dev/null 2>&1 || true

  # Fallback codename if missing
  detect_os_release
  CODENAME="${OS_CODENAME:-jammy}"

  # Add ROCm repo (version can be overridden with ROCM_VER env)
  ROCM_VER="${ROCM_VER:-6.0}"
  echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/${ROCM_VER} ${CODENAME} main" \
    | $SUDO tee /etc/apt/sources.list.d/rocm.list >/dev/null

  $SUDO apt update

  # Kernel driver + ROCm userspace
  $SUDO apt install -y amdgpu-dkms rocm-dev rocm-libs rocm-utils hip-runtime-amd || {
    echo "⚠️  ROCm meta-packages failed. Trying amdgpu-install helper..."
    # As a fallback, try amdgpu-install meta helper
    if ! is_cmd curl; then $SUDO apt install -y curl; fi
    # Attempt to fetch latest amdgpu-install for your codename
    URL_BASE="https://repo.radeon.com/amdgpu-install/latest/ubuntu/${CODENAME}/"
    PKG=$(curl -fsSL "$URL_BASE" | grep -o 'amdgpu-install_[^"]*\.deb' | head -n1 || true)
    if [[ -n "${PKG}" ]]; then
      curl -fsSL -o /tmp/amdgpu-install.deb "${URL_BASE}${PKG}"
      $SUDO apt install -y /tmp/amdgpu-install.deb
      $SUDO amdgpu-install --usecase=rocm -y || true
    else
      echo "❌ Could not locate amdgpu-install package automatically."
      echo "   Please see AMD ROCm install docs for your Ubuntu version."
    fi
  }

  # Groups for access to /dev/dri render nodes
  $SUDO usermod -a -G video "${SUDO_USER:-$USER}" || true
  $SUDO usermod -a -G render "${SUDO_USER:-$USER}" || true

  echo "✅ ROCm packages installed. Reboot recommended."
  echo "ℹ️  After reboot, verify /dev/kfd exists: ls -l /dev/kfd"
}

# ---- AMD ROCm (pacman/Arch) --------------------------------------------------

install_amd_rocm_pacman() {
  echo "⚠️  AMD ROCm on Arch is NOT officially supported. Proceeding best-effort."
  $SUDO pacman -Sy --noconfirm base-devel git rocm-smi-lib || true

  # Try AUR helpers if present
  if is_cmd yay; then
    yay -Sy --noconfirm hip-runtime-amd rocm-dev rocm-hip-sdk || true
  elif is_cmd paru; then
    paru -Sy --noconfirm hip-runtime-amd rocm-dev rocm-hip-sdk || true
  else
    echo "⚠️  No AUR helper found (yay/paru). Attempting manual AUR clone for hip-runtime-amd..."
    cd /tmp
    git clone https://aur.archlinux.org/hip-runtime-amd.git || true
    (cd hip-runtime-amd && makepkg -si --noconfirm) || true
  fi

  $SUDO usermod -a -G video "${SUDO_USER:-$USER}" || true
  $SUDO usermod -a -G render "${SUDO_USER:-$USER}" || true

  echo "ℹ️  Reboot and check for /dev/kfd. If it is missing, ROCm acceleration will not work on Arch."
}

# ---- Vulkan fallback (optional) ----------------------------------------------

install_vulkan_apt() {
  echo "===> Installing Vulkan userspace (Mesa) for fallback acceleration"
  $SUDO apt update
  $SUDO apt install -y mesa-vulkan-drivers vulkan-tools
  echo "✅ Vulkan userspace installed."
}

install_vulkan_pacman() {
  echo "===> Installing Vulkan userspace (Mesa) for fallback acceleration"
  $SUDO pacman -Sy --noconfirm vulkan-tools vulkan-icd-loader
  # Try to install vendor-specific ICDs
  if [[ "${GPU_VENDOR}" == "amd" ]]; then
    $SUDO pacman -Sy --noconfirm vulkan-radeon || true
  elif [[ "${GPU_VENDOR}" == "nvidia" ]]; then
    # NVIDIA Vulkan handled by driver
    :
  else
    # Intel or unknown
    $SUDO pacman -Sy --noconfirm vulkan-intel || true
  fi
  echo "✅ Vulkan userspace installed."
}

# ---- Tests -------------------------------------------------------------------

show_next_steps() {
  echo
  echo "==================== NEXT STEPS ===================="
  echo "• Reboot your machine to finalize driver/modules & group changes."
  echo "• NVIDIA quick test (after reboot):"
  echo "    docker run --rm --gpus all nvidia/cuda:12.3.1-base-ubuntu22.04 nvidia-smi"
  echo "• AMD ROCm quick test (after reboot):"
  echo "    docker run --rm --device=/dev/kfd --device=/dev/dri rocm/rocm-terminal \\\n      bash -lc 'rocminfo | head -n 40'"
  echo "• Vulkan fallback (Ollama): start with OLLAMA_VULKAN=1 and map /dev/dri"
  echo "===================================================="
}

# ---- Main --------------------------------------------------------------------

need_sudo
detect_pkg_mgr
detect_os_release
detect_gpu_vendor
ensure_docker_warning

echo "Detected package manager: ${PKG}"
echo "Detected OS: ${OS_ID:-unknown} ${OS_CODENAME:-}"
echo "Detected GPU vendor: ${GPU_VENDOR}"

case "${PKG}" in
  apt)
    if [[ "${GPU_VENDOR}" == "nvidia" ]]; then
      install_nvidia_apt
      install_vulkan_apt   # optional: Vulkan is harmless and useful for testing
    elif [[ "${GPU_VENDOR}" == "amd" ]]; then
      install_amd_rocm_apt
      install_vulkan_apt
    else
      echo "GPU vendor unknown. Installing Vulkan fallback only."
      install_vulkan_apt
    fi
    ;;
  pacman)
    if [[ "${GPU_VENDOR}" == "nvidia" ]]; then
      install_nvidia_pacman
      install_vulkan_pacman
    elif [[ "${GPU_VENDOR}" == "amd" ]]; then
      install_amd_rocm_pacman
      install_vulkan_pacman
    else
      echo "GPU vendor unknown. Installing Vulkan fallback only."
      install_vulkan_pacman
    fi
    ;;
esac

show_next_steps

