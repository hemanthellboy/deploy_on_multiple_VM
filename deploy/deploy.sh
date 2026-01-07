#!/usr/bin/env bash
set -euo pipefail

# Multi-VM orchestrator
# Usage: ./deploy/deploy.sh [inventory_file] <app> <version> [--batch-size N] [--dry-run]

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
INVENTORY_FILE="${ROOT_DIR}/inventory/prod.env"
BATCH_SIZE=${BATCH_SIZE:-3}
DRY_RUN=0

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: $0 [inventory_file] <app> <version> [--batch-size N] [--dry-run]
Examples:
  $0 inventory/prod.env loan-service 1.2.5 --dry-run
EOF
  exit 0
fi

if [[ -f "${1:-}" && -r "${1:-}" && ! -z "${2:-}" && ! -z "${3:-}" ]]; then
  INVENTORY_FILE="$1"
  APP="$2"
  VERSION="$3"
  shift 3
else
  APP="${2:-}"
  VERSION="${3:-}"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch-size)
      BATCH_SIZE="$2"; shift 2;;
    --dry-run)
      DRY_RUN=1; shift;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

if [[ -z "$APP" || -z "$VERSION" ]]; then
  echo "Missing app or version. See --help"; exit 2
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
  echo "Inventory file not found: $INVENTORY_FILE"; exit 2
fi

DEPLOY_ID=$(date -u +%Y%m%dT%H%M%SZ)-$$
LOG_FILE="$ROOT_DIR/state/deployments.log"
TMP_DIR="$ROOT_DIR/tmp"
mkdir -p "$TMP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

mapfile -t TARGETS < <(grep -v '^\s*#' "$INVENTORY_FILE" | sed '/^\s*$/d')
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "No targets in inventory"; exit 2
fi

echo "Deployment ID: $DEPLOY_ID"
echo "App: $APP Version: $VERSION"
echo "Targets (${#TARGETS[@]}):"; printf ' - %s\n' "${TARGETS[@]}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY-RUN: No remote writes will be performed"
  echo
  echo "Planned per-VM step order:"
  for s in "$ROOT_DIR/apps/$APP/steps"/*.sh; do
    echo "  $(basename "$s")"
  done
  exit 0
fi

declare -A pid_to_vm
declare -A vm_status

batch_count=0
i=0
while [[ $i -lt ${#TARGETS[@]} ]]; do
  batch_count=$((batch_count+1))
  batch_end=$((i + BATCH_SIZE))
  if [[ $batch_end -gt ${#TARGETS[@]} ]]; then batch_end=${#TARGETS[@]}; fi
  batch=("${TARGETS[@]:i:batch_end-i}")

  echo "Starting batch $batch_count with ${#batch[@]} targets"

  # Launch deploy_remote.sh on each VM in background
  for vm in "${batch[@]}"; do
    outFile="$TMP_DIR/${DEPLOY_ID}_${vm//[:\/]/_}.log"
    echo " - Launching $vm -> log: $outFile"

    # create a tarball stream of the deployment bundle and extract+run on remote as centos
    (
      tar -C "$ROOT_DIR" -cz "deploy_remote.sh" "lib" "apps/$APP" "artifacts" "state" 2>/dev/null |
      ssh -o StrictHostKeyChecking=yes -o BatchMode=yes "$vm" \
        "sudo -u centos bash -c 'set -euo pipefail; dst=/tmp/deploy_run_${DEPLOY_ID}; rm -rf \"$dst\"; mkdir -p \"$dst\"; tar -xz -C \"$dst\"; bash \"$dst/deploy_remote.sh\" \"$vm\" \"$APP\" \"$VERSION\" \"$DEPLOY_ID\"'" \
      > "$outFile" 2>&1 || echo "REMOTE_FAILED"
    ) &
    pid=$!
    pid_to_vm[$pid]="$vm"
    vm_status[$vm]=RUNNING
  done

  # wait for all in this batch
  batch_failed=0
  for pid in "${!pid_to_vm[@]}"; do
    vm=${pid_to_vm[$pid]}
    if ! wait "$pid"; then
      echo "VM $vm failed (see $TMP_DIR/${DEPLOY_ID}_${vm//[:\/]/_}.log)"
      vm_status[$vm]=FAILED
      batch_failed=1
    else
      echo "VM $vm succeeded"
      vm_status[$vm]=SUCCESS
    fi
  done

  if [[ $batch_failed -ne 0 ]]; then
    echo "Batch $batch_count failed. Exiting with failure."
    exit 1
  fi

  # clear pid map for next batch
  pid_to_vm=()
  i=$batch_end
done

echo "All batches completed successfully"
exit 0
