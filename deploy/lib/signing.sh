#!/usr/bin/env bash
set -euo pipefail

# Artifact signing and integrity helpers.

_signing_trim() {
	local trimmed="${1}"
	trimmed="${trimmed#${trimmed%%[![:space:]]*}}"
	trimmed="${trimmed%${trimmed##*[![:space:]]}}"
	printf '%s' "$trimmed"
}

verify_sha256_signature() {
	local file="$1"
	local signature_file="$2"

	if ! command -v sha256sum >/dev/null 2>&1; then
		echo "sha256sum not available for signature validation" >&2
		return 1
	fi
	if [[ ! -f "$signature_file" ]]; then
		echo "signature file missing: $signature_file" >&2
		return 1
	fi

	local expected
	expected=$(awk 'NF {print $1; exit}' "$signature_file")
	expected=$(_signing_trim "${expected:-}")
	if [[ -z "$expected" ]]; then
		echo "signature file empty: $signature_file" >&2
		return 1
	fi

	local actual
	actual=$(sha256sum "$file" | awk '{print $1}')
	if [[ "$actual" != "$expected" ]]; then
		echo "checksum mismatch for $file" >&2
		return 1
	fi
	return 0
}

verify_gpg_signature() {
	local file="$1"
	local signature_file="$2"

	if ! command -v gpg >/dev/null 2>&1; then
		echo "gpg not available for signature validation" >&2
		return 1
	fi

	if ! gpg --verify "$signature_file" "$file" >/dev/null 2>&1; then
		echo "gpg signature verification failed for $file" >&2
		return 1
	fi
	return 0
}

verify_artifact_signature() {
	local file="$1"
	local explicit_sig="${2:-}"

	if [[ -n "$explicit_sig" ]]; then
		if [[ "$explicit_sig" == *.asc || "$explicit_sig" == *.gpg || "$explicit_sig" == *.sig ]]; then
			verify_gpg_signature "$file" "$explicit_sig"
			return $?
		fi
		verify_sha256_signature "$file" "$explicit_sig"
		return $?
	fi

	if [[ -f "${file}.sha256" ]]; then
		verify_sha256_signature "$file" "${file}.sha256"
		return $?
	fi

	if [[ -f "${file}.asc" ]]; then
		verify_gpg_signature "$file" "${file}.asc"
		return $?
	fi

	if [[ -f "${file}.sig" ]]; then
		verify_gpg_signature "$file" "${file}.sig"
		return $?
	fi

	# No signature supplied: treat as unsigned (pass-through).
	return 0
}
