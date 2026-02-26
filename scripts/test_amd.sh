docker run --rm --device=/dev/kfd --device=/dev/dri rocm/rocm-terminal \
  bash -lc 'rocminfo | head -n 40'
