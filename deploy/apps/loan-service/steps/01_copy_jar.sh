#!/usr/bin/env bash
set -euo pipefail

# Step: copy jar to target lib with backup and checksum validation

precheck() {
  # Expect artifact to be in bundle artifacts directory
  SRC="$BASE_DIR/artifacts/$JAR_NAME"
  if [[ ! -f "$SRC" ]]; then
    echo "artifact_missing: $SRC" >&2
    return 1
  fi
  if ! verify_artifact_signature "$SRC"; then
    echo "artifact_signature_invalid: $SRC" >&2
    return 1
  fi
  return 0
}

execute() {
  local dst_dir="$TARGET_LIB_DIR"
  local src="$BASE_DIR/artifacts/$JAR_NAME"
  mkdir -p "$dst_dir/.backup"
  if [[ -f "$dst_dir/$JAR_NAME" ]]; then
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    mv "$dst_dir/$JAR_NAME" "$dst_dir/.backup/${JAR_NAME}.${ts}" || return 1
  fi
  # copy as centos (this script runs as centos)
  cp -p "$src" "$dst_dir/" || return 1
  chown centos:centos "$dst_dir/$JAR_NAME" || true
  return 0
}

verify() {
  local src="$BASE_DIR/artifacts/$JAR_NAME"
  local dst="$TARGET_LIB_DIR/$JAR_NAME"
  if [[ ! -f "$dst" ]]; then
    echo "dst_missing: $dst" >&2; return 1
  fi
  srcsum=$(sha256sum "$src" 2>/dev/null | awk '{print $1}') || return 1
  dstsum=$(sha256sum "$dst" 2>/dev/null | awk '{print $1}') || return 1
  if [[ "$srcsum" != "$dstsum" ]]; then
    echo "checksum_mismatch" >&2; return 1
  fi
  # ownership
  validate_owned_by_centos "$dst" || return 1
  validate_no_world_writable "$dst" || return 1
  return 0
}

rollback() {
  # restore latest backup if exists
  local dst_dir="$TARGET_LIB_DIR"
  if compgen -G "$dst_dir/.backup/${JAR_NAME}.*" >/dev/null; then
    latest=$(ls -1t "$dst_dir/.backup/${JAR_NAME}.*" | head -n1)
    mv "$latest" "$dst_dir/$JAR_NAME" || return 1
    chown centos:centos "$dst_dir/$JAR_NAME" || true
    return 0
  fi
  # if no backup, remove the copied file
  rm -f "$dst_dir/$JAR_NAME" || true
  return 0
}
