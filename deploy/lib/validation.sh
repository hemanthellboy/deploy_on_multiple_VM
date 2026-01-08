#!/usr/bin/env bash
set -euo pipefail

# Validation helpers to be used in verification step scripts

validate_file_exists() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "MISSING: $path" >&2
    return 1
  fi
  return 0
}

validate_owned_by_centos() {
  local path="$1"
  owner=$(stat -c '%U:%G' "$path" 2>/dev/null || stat -f '%Su:%Sg' "$path")
  if [[ "$owner" != "centos:centos" ]]; then
    echo "BAD_OWNER: $path -> $owner" >&2
    return 1
  fi
  return 0
}

validate_no_world_writable() {
  local path="$1"
  if [[ -e "$path" ]]; then
    perms=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
    if [[ $((perms & 2)) -ne 0 ]]; then
      echo "WORLD_WRITABLE: $path ($perms)" >&2
      return 1
    fi
  fi
  return 0
}

validate_xml() {
  local xmlfile="$1"
  if ! command -v xmllint >/dev/null 2>&1; then
    echo "xmllint not installed" >&2
    return 1
  fi
  if ! xmllint --noout "$xmlfile" >/dev/null 2>&1; then
    echo "XML_INVALID: $xmlfile" >&2
    return 1
  fi
  return 0
}

health_check_url() {
  local url="$1"
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not installed" >&2
    return 1
  fi
  if ! curl -sfS "$url" >/dev/null 2>&1; then
    echo "HEALTH_CHECK_FAILED: $url" >&2
    return 1
  fi
  return 0
}

health_check_command() {
  local command="$1"
  if [[ -z "$command" ]]; then
    echo "HEALTH_CHECK_COMMAND_EMPTY" >&2
    return 1
  fi
  if ! bash -o pipefail -c "$command" >/dev/null 2>&1; then
    echo "HEALTH_CHECK_COMMAND_FAILED: $command" >&2
    return 1
  fi
  return 0
}

run_health_check_spec() {
  local spec="$1"
  if [[ -z "$spec" ]]; then
    echo "EMPTY_HEALTH_CHECK_SPEC" >&2
    return 1
  fi

  local type="${spec%%:*}"
  local value="${spec#*:}"
  if [[ "$type" == "$value" ]]; then
    value=""
  fi

  case "$type" in
    url)
      health_check_url "$value"
      ;;
    command)
      health_check_command "$value"
      ;;
    *)
      echo "UNKNOWN_HEALTH_CHECK: $spec" >&2
      return 1
      ;;
  esac
}
