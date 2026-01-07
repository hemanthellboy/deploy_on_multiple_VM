#!/usr/bin/env bash
set -euo pipefail

# logger for remote and local
# Expects STATE_FILE to be set for remote side

log_remote() {
  # timestamp | deployment_id | app | version | vm | step | status | message
  local deployment_id="$1" app="$2" version="$3" vm="$4" step="$5" message="$6"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "$ts | $deployment_id | $app | $version | $vm | $step | $message" >> "${STATE_FILE:-/tmp/deploy_state.log}"
  # also echo to stdout for the orchestrator to capture
  echo "$ts | $deployment_id | $app | $version | $vm | $step | $message"
}

log_local() {
  local deployment_id="$1" app="$2" version="$3" vm="$4" step="$5" message="$6"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local logfile="$(cd "$(dirname "$0")/../.." && pwd)/state/deployments.log"
  echo "$ts | $deployment_id | $app | $version | $vm | $step | $message" >> "$logfile"
}
