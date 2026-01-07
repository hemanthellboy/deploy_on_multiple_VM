#!/usr/bin/env bash
set -euo pipefail

# Step: edit XML using xmllint only (no regex)

precheck() {
  if [[ ! -f "$XML_PATH" ]]; then
    echo "xml_missing: $XML_PATH" >&2; return 1
  fi
  if ! command -v xmllint >/dev/null 2>&1; then
    echo "xmllint_missing" >&2; return 1
  fi
  return 0
}

execute() {
  # backup
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  cp -p "$XML_PATH" "$XML_PATH.bak.${ts}"
  chown centos:centos "$XML_PATH.bak.${ts}" || true

  # apply edits defined in XML_EDITS array in deploy.conf
  for edit in "${XML_EDITS[@]:-}"; do
    IFS='|' read -r xpath value <<< "$edit"
    # use xmllint --shell to set value
    xmllint --shell "$XML_PATH" <<EOF >/dev/null 2>&1 || return 1
cd $xpath
set $value
save
EOF
  done
  return 0
}

verify() {
  validate_xml "$XML_PATH" || return 1
  validate_owned_by_centos "$XML_PATH" || return 1
  validate_no_world_writable "$XML_PATH" || return 1
  return 0
}

rollback() {
  # restore latest backup
  if compgen -G "$XML_PATH.bak.*" >/dev/null; then
    latest=$(ls -1t "$XML_PATH.bak.*" | head -n1)
    cp -p "$latest" "$XML_PATH"
    chown centos:centos "$XML_PATH" || true
    return 0
  fi
  return 1
}
