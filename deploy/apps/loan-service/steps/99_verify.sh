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

  # health check
  if [[ -n "${HEALTH_URL:-}" ]]; then
    health_check_url "$HEALTH_URL" || return 1
  fi
  return 0
}

verify() {
  return 0
}

rollback() {
  # no-op; previous steps handle rollback
  return 0
}
