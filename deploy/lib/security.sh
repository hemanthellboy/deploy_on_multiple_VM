#!/usr/bin/env bash
set -euo pipefail

# Security checks. Run as centos

_sudo_trim() {
  local trimmed="${1}";
  trimmed="${trimmed#${trimmed%%[![:space:]]*}}"  # ltrim
  trimmed="${trimmed%${trimmed##*[![:space:]]}}"  # rtrim
  printf '%s' "$trimmed"
}

ensure_sudo_is_restricted() {
  local policy="${SUDO_POLICY:-}"
  local invoking_user="${SUDO_USER:-}"

  if [[ -z "$policy" ]]; then
    echo "sudo allowlist missing (SUDO_POLICY not provided)" >&2
    return 1
  fi
  if [[ -z "$invoking_user" ]]; then
    echo "sudo allowlist verification failed: SUDO_USER unset" >&2
    return 1
  fi

  # Allowed targets and commands may be customized via environment variables.
  IFS=',' read -r -a allowed_targets <<< "${ALLOWED_SUDO_TARGETS:-centos}"
  IFS=',' read -r -a allowed_commands <<< "${ALLOWED_SUDO_COMMANDS:-/bin/bash,/usr/bin/bash,/bin/sh,/usr/bin/env bash}"

  local current_target=""
  local current_payload=""
  local violation=0
  local valid_entry=0

  _flush_entry() {
    local target="$1"
    local payload="$2"
    if [[ -z "$target" ]]; then
      return
    fi

    local target_trimmed=$(_sudo_trim "$target")
    local allowed_target=1
    local t
    for t in "${allowed_targets[@]}"; do
      if [[ "$target_trimmed" == "$t" ]]; then
        allowed_target=0
        break
      fi
    done
    if [[ $allowed_target -ne 0 ]]; then
      echo "sudo allowlist violation: disallowed target ($target_trimmed)" >&2
      violation=1
      return
    fi

    local cleaned_payload="$payload"
    cleaned_payload=${cleaned_payload#NOPASSWD: }
    cleaned_payload=${cleaned_payload#PASSWD: }
    cleaned_payload=${cleaned_payload#SETENV: }
    cleaned_payload=${cleaned_payload#NOPASSWD: }
    cleaned_payload=$(_sudo_trim "$cleaned_payload")

    if [[ -z "$cleaned_payload" ]]; then
      echo "sudo allowlist violation: empty command list for target $target_trimmed" >&2
      violation=1
      return
    fi

    IFS=',' read -r -a commands_list <<< "$cleaned_payload"
    local entry_has_valid=0
    local cmd
    for cmd in "${commands_list[@]}"; do
      local command_trimmed=$(_sudo_trim "$cmd")
      if [[ -z "$command_trimmed" ]]; then
        continue
      fi
      if [[ "$command_trimmed" == ALL* || "$command_trimmed" == *'*'* ]]; then
        echo "sudo allowlist violation: wildcard command ($command_trimmed)" >&2
        violation=1
        return
      fi

      local allowed_cmd=1
      local allowed
      for allowed in "${allowed_commands[@]}"; do
        if [[ "$command_trimmed" == "$allowed" || "$command_trimmed" == "$allowed "* ]]; then
          allowed_cmd=0
          break
        fi
      done
      if [[ $allowed_cmd -ne 0 ]]; then
        echo "sudo allowlist violation: command not in allowlist ($command_trimmed)" >&2
        violation=1
        return
      fi
      entry_has_valid=1
    done

    if [[ $entry_has_valid -eq 1 ]]; then
      valid_entry=1
    fi
  }

  while IFS= read -r raw_line; do
    local line=$(_sudo_trim "$raw_line")
    [[ -z "$line" ]] && continue
    [[ "$line" == User* ]] && continue
    [[ "$line" == Matching* ]] && continue
    [[ "$line" == Defaults* ]] && continue
    [[ "$line" == Runas* ]] && continue

    if [[ "$line" =~ ^\(([^\)]+)\)[[:space:]]*(.*)$ ]]; then
      if [[ -n "$current_target" ]]; then
        _flush_entry "$current_target" "$current_payload"
        if [[ $violation -eq 1 ]]; then
          break
        fi
      fi
      current_target="${BASH_REMATCH[1]}"
      current_payload="${BASH_REMATCH[2]}"
    else
      if [[ -n "$current_target" ]]; then
        current_payload+=" ${line}"
      fi
    fi
  done <<< "$policy"

  if [[ $violation -eq 0 ]]; then
    _flush_entry "$current_target" "$current_payload"
  fi

  if [[ $violation -ne 0 ]]; then
    return 1
  fi
  if [[ $valid_entry -eq 0 ]]; then
    echo "sudo allowlist violation: no valid commands found for $invoking_user" >&2
    return 1
  fi

  return 0
}
