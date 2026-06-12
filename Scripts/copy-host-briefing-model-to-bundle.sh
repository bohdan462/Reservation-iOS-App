#!/bin/bash
# Copies the host briefing GGUF into the app bundle when present locally.
# Run Scripts/fetch-host-briefing-model.sh first on your Mac.
set -euo pipefail

MODEL_FILENAME="host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf"
MODEL_SRC="${SRCROOT}/LocalModels/HostIntelligence/${MODEL_FILENAME}"
DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
DEST_PATH="${DEST_DIR}/${MODEL_FILENAME}"

echo "[MODEL_BUNDLE_COPY] source=${MODEL_SRC}"
echo "[MODEL_BUNDLE_COPY] destination=${DEST_PATH}"

if [[ -f "${MODEL_SRC}" ]]; then
  mkdir -p "${DEST_DIR}"
  if [[ -f "${DEST_PATH}" ]] && cmp -s "${MODEL_SRC}" "${DEST_PATH}"; then
    SIZE_BYTES=$(stat -f%z "${DEST_PATH}")
    echo "[MODEL_BUNDLE_COPY] copied=false (already up to date) sizeBytes=${SIZE_BYTES}"
  else
    cp -f "${MODEL_SRC}" "${DEST_PATH}"
    SIZE_BYTES=$(stat -f%z "${DEST_PATH}")
    echo "[MODEL_BUNDLE_COPY] copied=true sizeBytes=${SIZE_BYTES}"
  fi
else
  echo "[MODEL_BUNDLE_COPY] copied=false modelMissing=true"
  echo "warning: Host briefing GGUF not found at ${MODEL_SRC}"
  echo "warning: Run Scripts/fetch-host-briefing-model.sh, then rebuild to install on a physical device."
  echo "warning: Or import a .gguf from Files inside Host Intelligence settings on the device."
  # Fail hard for Release/Archive builds so TestFlight never ships without the model.
  if [[ "${CONFIGURATION}" == "Release" ]]; then
    echo "error: Model file is required for Release builds. App would ship without on-device AI."
    exit 1
  fi
fi
