#!/usr/bin/env bash
set -euo pipefail

# Step: extract any extra zips listed in EXRA_ZIPS (defined in deploy.conf as EXTRA_ZIPS)

precheck() {
  # nothing fatal if no extra zips
  return 0
}

execute() {
  if [[ -z "${EXTRA_ZIPS[*]-}" ]]; then
    return 0
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip_missing" >&2
    return 1
  fi

  local backup_dir="${TARGET_CLASSES_DIR}.extra-bak-${DEPLOY_ID}"
  if [[ -d "$TARGET_CLASSES_DIR" ]]; then
    rm -rf "$backup_dir"
    cp -a "$TARGET_CLASSES_DIR" "$backup_dir" || return 1
  fi

  mkdir -p "$TARGET_CLASSES_DIR"

  for z in "${EXTRA_ZIPS[@]}"; do
    local src="$BASE_DIR/artifacts/$z"
    if [[ ! -f "$src" ]]; then
      echo "extra_zip_missing: $z" >&2
      return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/extra_${DEPLOY_ID}_${z//[^A-Za-z0-9]/}_XXXX")
    unzip -q "$src" -d "$tmpdir" || { rm -rf "$tmpdir"; return 1; }

    if [[ -d "$tmpdir" ]]; then
      tar -C "$tmpdir" -cf "$tmpdir/content.tar" . || { rm -rf "$tmpdir"; return 1; }
      tar -C "$TARGET_CLASSES_DIR" -xf "$tmpdir/content.tar" || { rm -rf "$tmpdir"; return 1; }
      rm -f "$tmpdir/content.tar"
    fi

    rm -rf "$tmpdir"
  done

  chown -R centos:centos "$TARGET_CLASSES_DIR" || true
  return 0
}

verify() {
  # ensure no world-writable files in classes dir
  validate_no_world_writable "$TARGET_CLASSES_DIR" || return 1
  validate_owned_by_centos "$TARGET_CLASSES_DIR" || return 1
  return 0
}

rollback() {
  local backup_dir="${TARGET_CLASSES_DIR}.extra-bak-${DEPLOY_ID}"
  if [[ -d "$backup_dir" ]]; then
    rm -rf "$TARGET_CLASSES_DIR" || true
    mv "$backup_dir" "$TARGET_CLASSES_DIR" || return 1
    chown -R centos:centos "$TARGET_CLASSES_DIR" || true
  fi
  return 0
}
