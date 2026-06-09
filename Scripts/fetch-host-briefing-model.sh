#!/usr/bin/env bash
#
# Manual developer script — downloads the host briefing GGUF for local testing.
# Not run during Xcode builds. The iOS app never downloads models at runtime.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODEL_DIR="${REPO_ROOT}/LocalModels/HostIntelligence"
EXPECTED_FILENAME="host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf"
OUTPUT_PATH="${MODEL_DIR}/${EXPECTED_FILENAME}"

# Source file on Hugging Face (bartowski quant). Rename to app-expected filename after download.
SOURCE_URL="https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf"

# Set after verifying the downloaded file on your machine. Leave as TODO to skip verification.
EXPECTED_SHA256="6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653"

echo "==> Host Intelligence briefing model fetch"
echo "Repository root: ${REPO_ROOT}"
echo "Output directory: ${MODEL_DIR}"
echo "Expected filename: ${EXPECTED_FILENAME}"
echo

mkdir -p "${MODEL_DIR}"

if [[ -f "${OUTPUT_PATH}" ]]; then
  echo "Existing file found at:"
  echo "  ${OUTPUT_PATH}"
  echo "Remove it first if you want a fresh download."
  ls -lh "${OUTPUT_PATH}"
  exit 0
fi

TEMP_PATH="${OUTPUT_PATH}.download"
echo "==> Downloading from:"
echo "  ${SOURCE_URL}"
echo

if command -v curl >/dev/null 2>&1; then
  curl --fail --location --progress-bar "${SOURCE_URL}" --output "${TEMP_PATH}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${TEMP_PATH}" "${SOURCE_URL}"
else
  echo "error: curl or wget is required." >&2
  exit 1
fi

mv "${TEMP_PATH}" "${OUTPUT_PATH}"

if [[ "${EXPECTED_SHA256}" != "TODO" && -n "${EXPECTED_SHA256}" ]]; then
  echo "==> Verifying SHA256"
  if command -v shasum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(shasum -a 256 "${OUTPUT_PATH}" | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA256="$(sha256sum "${OUTPUT_PATH}" | awk '{print $1}')"
  else
    echo "warning: no shasum/sha256sum available; skipping hash verification." >&2
    ACTUAL_SHA256=""
  fi

  if [[ -n "${ACTUAL_SHA256}" ]]; then
    if [[ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]]; then
      echo "error: SHA256 mismatch." >&2
      echo "  expected: ${EXPECTED_SHA256}" >&2
      echo "  actual:   ${ACTUAL_SHA256}" >&2
      rm -f "${OUTPUT_PATH}"
      exit 1
    fi
    echo "SHA256 verified."
  fi
else
  echo "==> SHA256 verification skipped (EXPECTED_SHA256 is TODO)."
  echo "    After confirming the file, set EXPECTED_SHA256 in this script."
fi

FILE_SIZE="$(du -h "${OUTPUT_PATH}" | awk '{print $1}')"
echo
echo "==> Download complete"
echo "Model path:"
echo "  ${OUTPUT_PATH}"
echo "File size:"
echo "  ${FILE_SIZE}"
echo
echo "==> Next steps (manual — not automated by the app)"
echo "1. This file is gitignored. Do not commit it."
echo "2. Install on a physical device for real inference testing."
echo "3. Copy to Application Support expected by the app:"
echo "     Library/Application Support/HostIntelligence/Models/${EXPECTED_FILENAME}"
echo
echo "   Example (replace DEVICE_UDID and APP_CONTAINER):"
echo "     APP_SUPPORT=\"~/Library/Developer/Xcode/DeviceLogs/...\"  # use Xcode → Devices container path"
echo "     mkdir -p \"\${APP_SUPPORT}/HostIntelligence/Models\""
echo "     cp \"${OUTPUT_PATH}\" \"\${APP_SUPPORT}/HostIntelligence/Models/${EXPECTED_FILENAME}\""
echo
echo "   Or use Xcode: Window → Devices and Simulators → select device → installed app →"
echo "   gear icon → Download Container → copy into Library/Application Support/HostIntelligence/Models/"
echo "   then upload the modified container back (developer testing only)."
echo
echo "4. Launch Tryzub Host on the device."
echo "5. Host Intelligence settings → enable enhanced briefing → provider: Local model."
echo "6. Developer diagnostics → confirm readiness is 'ready'."
echo "7. Tap 'Test Local Model Briefing' in diagnostics (device only)."
echo
echo "Production/TestFlight bundling is a later phase — this script is for local dev only."
