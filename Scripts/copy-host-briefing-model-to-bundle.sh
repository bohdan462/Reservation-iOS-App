#!/bin/bash
# Copies Host Intelligence GGUF model files into the app bundle.
#
# Build mode is controlled by REQUIRE_3B_HOST_MODEL (xcconfig / User-Defined build setting):
#
#   REQUIRE_3B_HOST_MODEL=1  — iPad demo / production intelligence build
#     - 3B model (host-wording-qwen2_5-3b-instruct-q4_k_m.gguf) is required.
#     - Build fails with a clear error if the 3B file is missing at its expected path.
#     - 0.5B model is optional — copied if present, not required; build does not fail.
#     - Deterministic template fallback always remains in the app code.
#
#   REQUIRE_3B_HOST_MODEL unset or 0 — default dev/debug builds
#     - Both models are optional; only a warning is emitted when missing.
#     - Release/Archive builds still fail if NEITHER model is present (original safety gate).
#
# Expected source location:  LocalModels/HostIntelligence/<filename>
# Run Scripts/fetch-host-briefing-model.sh first if you need to download the models.
#
set -euo pipefail

MODEL_3B_FILENAME="host-wording-qwen2_5-3b-instruct-q4_k_m.gguf"
MODEL_0_5B_FILENAME="host-briefing-qwen2_5-0_5b-instruct-q4_k_m.gguf"

SRC_DIR="${SRCROOT}/LocalModels/HostIntelligence"
MODEL_3B_SRC="${SRC_DIR}/${MODEL_3B_FILENAME}"
MODEL_0_5B_SRC="${SRC_DIR}/${MODEL_0_5B_FILENAME}"

DEST_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
MODEL_3B_DEST="${DEST_DIR}/${MODEL_3B_FILENAME}"
MODEL_0_5B_DEST="${DEST_DIR}/${MODEL_0_5B_FILENAME}"

REQUIRE_3B="${REQUIRE_3B_HOST_MODEL:-0}"

echo "[MODEL_BUNDLE_COPY] require3B=${REQUIRE_3B} configuration=${CONFIGURATION}"
echo "[MODEL_BUNDLE_COPY] source3B=${MODEL_3B_SRC}"
echo "[MODEL_BUNDLE_COPY] source0_5B=${MODEL_0_5B_SRC}"

# ── helpers ──────────────────────────────────────────────────────────────────

copy_if_changed() {
  local src="$1"
  local dest="$2"
  local label="$3"
  mkdir -p "$(dirname "${dest}")"
  if [[ -f "${dest}" ]] && cmp -s "${src}" "${dest}"; then
    local sizeBytes
    sizeBytes=$(stat -f%z "${dest}")
    echo "[MODEL_BUNDLE_COPY] ${label}copied=false (already up to date) sizeBytes=${sizeBytes}"
  else
    cp -f "${src}" "${dest}"
    local sizeBytes
    sizeBytes=$(stat -f%z "${dest}")
    echo "[MODEL_BUNDLE_COPY] ${label}copied=true sizeBytes=${sizeBytes}"
  fi
}

# ── 3B wording model ─────────────────────────────────────────────────────────

if [[ -f "${MODEL_3B_SRC}" ]]; then
  copy_if_changed "${MODEL_3B_SRC}" "${MODEL_3B_DEST}" "required3B"
  echo "[MODEL_BUNDLE_COPY] required3Bmissing=false"
else
  echo "[MODEL_BUNDLE_COPY] required3Bmissing=true"
  if [[ "${REQUIRE_3B}" == "1" ]]; then
    echo "error: 3B Host wording model is required for this build but missing at LocalModels/HostIntelligence/${MODEL_3B_FILENAME}"
    echo "error: Place the model at the path above, then rebuild."
    exit 1
  else
    echo "warning: 3B Host wording model not found at ${MODEL_3B_SRC}."
    echo "warning: App will fall back to 0.5B model or deterministic template wording."
  fi
fi

# ── 0.5B briefing model ───────────────────────────────────────────────────────
# When REQUIRE_3B=1, the 0.5B model is optional — copied if present but never
# required. Only legacy Release builds (REQUIRE_3B unset) fail without it.

SMALL_REQUIRED="0"
if [[ "${REQUIRE_3B}" != "1" && "${CONFIGURATION}" == "Release" ]]; then
  SMALL_REQUIRED="1"
fi

if [[ -f "${MODEL_0_5B_SRC}" ]]; then
  copy_if_changed "${MODEL_0_5B_SRC}" "${MODEL_0_5B_DEST}" "smallModel"
  echo "[MODEL_BUNDLE_COPY] smallModelCopied=true smallModelRequired=${SMALL_REQUIRED}"
else
  echo "[MODEL_BUNDLE_COPY] smallModelCopied=false smallModelRequired=${SMALL_REQUIRED}"
  if [[ "${SMALL_REQUIRED}" == "1" ]]; then
    echo "error: 0.5B Host briefing model is required for Release builds (REQUIRE_3B_HOST_MODEL not set)."
    echo "error: Run Scripts/fetch-host-briefing-model.sh, or set REQUIRE_3B_HOST_MODEL=1 to use the 3B model instead."
    exit 1
  elif [[ "${REQUIRE_3B}" == "1" ]]; then
    echo "warning: 0.5B model not present — not required for this iPad/demo build (3B is primary)."
  else
    echo "warning: 0.5B model not found. Run Scripts/fetch-host-briefing-model.sh, then rebuild."
    echo "warning: Or import a .gguf from Files inside Host Intelligence settings on the device."
  fi
fi
