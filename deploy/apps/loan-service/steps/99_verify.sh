#!/usr/bin/env bash
set -euo pipefail

# Final verification step

precheck() {
  return 0
}

execute() {
  # run validations
  validate_file_exists "$TARGET_LIB_DIR/$JAR_NAME" || return 1
  validate_owned_by_centos "$TARGET_LIB_DIR/$JAR_NAME" || return 1
  validate_no_world_writable "$TARGET_LIB_DIR/$JAR_NAME" || return 1

  validate_file_exists "$TARGET_CLASSES_DIR" || return 1
  validate_owned_by_centos "$TARGET_CLASSES_DIR" || return 1
  validate_no_world_writable "$TARGET_CLASSES_DIR" || return 1

  if [[ -f "$XML_PATH" ]]; then
    validate_xml "$XML_PATH" || return 1
  fi

  local checks=()
  if declare -p HEALTH_CHECKS >/dev/null 2>&1; then
    checks=("${HEALTH_CHECKS[@]}")
  fi
  if [[ ${#checks[@]} -eq 0 && -n "${HEALTH_URL:-}" ]]; then
    checks=("url:${HEALTH_URL}")
  fi

  local spec
  for spec in "${checks[@]}"; do
    [[ -z "$spec" ]] && continue
    run_health_check_spec "$spec" || return 1
  done
  return 0
}

verify() {
  return 0
}

rollback() {
  # no-op; previous steps handle rollback
  return 0
}
