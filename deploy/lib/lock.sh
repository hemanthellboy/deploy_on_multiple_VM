#!/usr/bin/env bash
set -euo pipefail

# Lock handling. Must be run as centos on remote host.
GLOBAL_LOCK_FILE="/var/run/deploy-global.lock"
VM_LOCK_FILE="/var/run/deploy.lock"

acquire_global_lock() {
  if [[ -e "$GLOBAL_LOCK_FILE" ]]; then
    echo "global lock exists" >&2
    return 1
  fi
  umask 077
  printf "%s\n" "$$" > "$GLOBAL_LOCK_FILE"
  chown centos:centos "$GLOBAL_LOCK_FILE" || true
  return 0
}

release_global_lock() {
  if [[ -e "$GLOBAL_LOCK_FILE" ]]; then
    rm -f "$GLOBAL_LOCK_FILE" || true
  fi
}

acquire_vm_lock() {
  if [[ -e "$VM_LOCK_FILE" ]]; then
    echo "vm lock exists" >&2
    return 1
  fi
  umask 077
  printf "%s\n" "$$" > "$VM_LOCK_FILE"
  chown centos:centos "$VM_LOCK_FILE" || true
  return 0
}

release_vm_lock() {
  if [[ -e "$VM_LOCK_FILE" ]]; then
    rm -f "$VM_LOCK_FILE" || true
  fi
}
