#!/usr/bin/env bash
set -euo pipefail

# This script runs on the remote host as centos via sudo -u centos
# Args: <vm> <app> <version> <deploy_id>

VM="$1"
APP="$2"
VERSION="$3"
DEPLOY_ID="$4"

BASE_DIR="/tmp/deploy_run_${DEPLOY_ID}"
WORK_DIR="$BASE_DIR/apps/$APP"
LIB_DIR="$BASE_DIR/lib"
STATE_FILE="$BASE_DIR/state/deployments.log"

export DEPLOY_ID VM APP VERSION BASE_DIR WORK_DIR LIB_DIR STATE_FILE

mkdir -p "$BASE_DIR"
touch "$STATE_FILE"

source "$LIB_DIR/logger.sh"
source "$LIB_DIR/lock.sh"
source "$LIB_DIR/rollback.sh"
source "$LIB_DIR/security.sh"
source "$LIB_DIR/validation.sh"

# Source app config (should set variables like JAR_NAME, TARGET_* etc). deploy.conf may reference VERSION
if [[ -f "$WORK_DIR/deploy.conf" ]]; then
  # export VERSION so deploy.conf can use it
  export VERSION
  # shellcheck source=/dev/null
  source "$WORK_DIR/deploy.conf"
fi

log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "start" "Deployment started"

# enforce global and per-vm locks (must be owned by centos)
acquire_global_lock || { log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "lock" "GLOBAL_LOCK_FAILED"; exit 2; }
acquire_vm_lock || { log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "lock" "VM_LOCK_FAILED"; release_global_lock; exit 2; }

trap 'release_vm_lock || true; release_global_lock || true' EXIT

# Ensure sudo is properly restricted where possible
ensure_sudo_is_restricted || { log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "security" "SUDO_ALLOWLIST_CHECK_FAILED"; rollback_all; exit 2; }

# Collect step list with deterministic ordering
shopt -s nullglob
step_files=("$WORK_DIR/steps"/*.sh)
shopt -u nullglob
IFS=$'\n' step_files=($(printf '%s\n' "${step_files[@]}" | sort))
unset IFS

if [[ ${#step_files[@]} -eq 0 ]]; then
  log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "error" "no_steps"
  rollback_all
  exit 2
fi

executed_steps=()

for step_path in "${step_files[@]}"; do
  step_name=$(basename "$step_path")
  unset -f precheck execute verify rollback 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$step_path"

  for fn in precheck execute verify rollback; do
    if ! declare -f "$fn" >/dev/null 2>&1; then
      log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "contract_missing:${fn}"
      rollback_sequence executed_steps
      exit 1
    fi
  done

  log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "precheck:start"
  if ! precheck; then
    log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "precheck:fail"
    rollback_sequence executed_steps
    exit 1
  fi

  log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "execute:start"
  if ! execute; then
    log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "execute:fail"
    rollback_sequence executed_steps
    exit 1
  fi

  log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "verify:start"
  if ! verify; then
    log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "verify:fail"
    rollback_sequence executed_steps
    exit 1
  fi

  executed_steps+=("$step_path")
  log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "success"
done

# Final verification step (idempotent)
log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "deployment" "complete"

release_vm_lock
release_global_lock

exit 0
