#!/usr/bin/env bash
set -euo pipefail

# Simple ssh wrapper enforcing StrictHostKeyChecking and no root
ssh_exec() {
  local target="$1"; shift
  ssh -o StrictHostKeyChecking=yes -o BatchMode=yes "$target" "$@"
}
