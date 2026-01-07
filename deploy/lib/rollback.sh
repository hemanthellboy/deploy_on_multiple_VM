#!/usr/bin/env bash
set -euo pipefail

# Rollback engine: rollback_sequence takes an array of executed step script paths (in order)

rollback_sequence() {
  local -n executed=$1
  # execute rollback in reverse order
  for (( idx=${#executed[@]}-1 ; idx>=0 ; idx-- )); do
    step_path="${executed[idx]}"
    step_name=$(basename "$step_path")
    log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "rollback:start"
    # source the script to get rollback() function
    unset -f precheck execute verify rollback 2>/dev/null || true
    if source "$step_path" && declare -f rollback >/dev/null 2>&1; then
      if ! rollback; then
        log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "rollback:fail"
        # mark manual intervention
        echo "ROLLBACK_FAILED_MANUAL_INTERVENTION: $step_name" >> "${STATE_FILE:-/tmp/deploy_state.log}"
        return 2
      else
        log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "rollback:ok"
      fi
    else
      log_remote "$DEPLOY_ID" "$APP" "$VERSION" "$VM" "$step_name" "rollback:missing"
      return 2
    fi
  done
  return 0
}

rollback_all() {
  # best-effort: if executed_steps exist in env, rollback them
  if declare -p executed_steps >/dev/null 2>&1; then
    rollback_sequence executed_steps || true
  fi
}
