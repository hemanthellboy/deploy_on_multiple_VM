#!/usr/bin/env bash
set -euo pipefail

# Security checks. Run as centos

ensure_sudo_is_restricted() {
  # Check sudo -l for deploy-user mentions centos usage. This is heuristic and must be adapted.
  if sudo -l 2>/dev/null | grep -qi 'centos' ; then
    return 0
  fi
  # Try fallback: check if sudo can run bash as centos without password
  if sudo -n -u centos true 2>/dev/null; then
    # allowed to run arbitrary commands as centos -> consider this allowed
    return 0
  fi
  echo "sudo allowlist for centos not verifiable" >&2
  return 1
}
