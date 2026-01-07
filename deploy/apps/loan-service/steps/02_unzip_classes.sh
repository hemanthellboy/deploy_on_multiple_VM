#!/usr/bin/env bash
set -euo pipefail

# Step: extract classes zip (if packaged) to TARGET_CLASSES_DIR atomically

precheck() {
  # Expect a classes.zip in the bundle or artifact path named classes.zip
  if [[ -f "$BASE_DIR/artifacts/classes.zip" ]]; then
    return 0
  fi
  # if no zip provided, skip this step successfully
  echo "no_classes_zip" >&2
  return 0
}

execute() {
  local zip="$BASE_DIR/artifacts/classes.zip"
  if [[ ! -f "$zip" ]]; then
    return 0
  fi
  tmpdir="/tmp/classes_${DEPLOY_ID}_$$"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"
  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip_missing" >&2; return 1
  fi
  unzip -q "$zip" -d "$tmpdir" || return 1
  # basic structure validation: must contain WEB-INF
  if [[ ! -d "$tmpdir/WEB-INF" ]]; then
    echo "invalid_structure: missing WEB-INF" >&2; return 1
  fi
  # backup current classes dir
  if [[ -d "$TARGET_CLASSES_DIR" ]]; then
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    mv "$TARGET_CLASSES_DIR" "$TARGET_CLASSES_DIR.bak.${ts}" || return 1
  fi
  # atomic move
  mv "$tmpdir" "$TARGET_CLASSES_DIR" || return 1
  chown -R centos:centos "$TARGET_CLASSES_DIR" || true
  return 0
}

verify() {
  validate_file_exists "$TARGET_CLASSES_DIR" || return 1
  validate_owned_by_centos "$TARGET_CLASSES_DIR" || return 1
  validate_no_world_writable "$TARGET_CLASSES_DIR" || return 1
  return 0
}

rollback() {
  # restore latest backup if present
  if compgen -G "$TARGET_CLASSES_DIR.bak.*" >/dev/null; then
    latest=$(ls -1t "$TARGET_CLASSES_DIR.bak.*" | head -n1)
    rm -rf "$TARGET_CLASSES_DIR" || true
    mv "$latest" "$TARGET_CLASSES_DIR" || return 1
    chown -R centos:centos "$TARGET_CLASSES_DIR" || true
    return 0
  fi
  # else remove created dir
  rm -rf "$TARGET_CLASSES_DIR" || true
  return 0
}
