#!/bin/bash
# Copies the host briefing GGUF into the app bundle when present locally.
# Run Scripts/fetch-host-briefing-model.sh first on your Mac.
set -euo pipefail

MODEL_FILENAME="host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf"
MODEL_SRC="${SRCROOT}/LocalModels/HostIntelligence/${MODEL_FILENAME}"
DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
DEST_PATH="${DEST_DIR}/${MODEL_FILENAME}"

if [[ -f "${MODEL_SRC}" ]]; then
  mkdir -p "${DEST_DIR}"
  if [[ -f "${DEST_PATH}" ]] && cmp -s "${MODEL_SRC}" "${DEST_PATH}"; then
    echo "Host briefing model already up to date in app bundle."
  else
    cp -f "${MODEL_SRC}" "${DEST_PATH}"
    echo "Copied host briefing model into app bundle."
  fi
else
  echo "warning: Host briefing GGUF not found at ${MODEL_SRC}"
  echo "warning: Run Scripts/fetch-host-briefing-model.sh, then rebuild to install on a physical device."
  echo "warning: Or import a .gguf from Files inside Host Intelligence settings on the device."
fi
