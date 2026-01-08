# Deployment Framework

🔥 **What problem this solves**
- Keeps multi-VM Java deployments consistent, reversible, and auditable without relying on heavy tooling.
- Eliminates snowflake deploy scripts by enforcing a uniform, tested step contract for every service.

❌ **The pain today**
- Manual SSH loops, forgotten hosts, and risky `scp` uploads that leave clusters half-updated.
- No automatic rollback, no locking, and no centralized audit of who deployed what and when.

✔️ **What this repo fixes**
- Provides a pure-bash orchestrator that runs batched deploys across *all* inventory hosts, with enforced locks, checksums, XML-safe edits, and automatic rollback when anything fails.
- Ships with reusable libraries (`lib/*.sh`) so every app reuses the same hardened primitives for logging, rollback, validation, and security.

🚀 **Features**
- Parallel batches across VMs; sequential, contract-driven steps per host.
- Mandatory `/var/run` locks (global + per-host) owned by `centos`.
- Automatic reverse-order rollback with manual-intervention alerts if recovery fails.
- Strict SSH model: connect as `deploy-user`, switch to `centos`, `StrictHostKeyChecking=yes` enforced.
- Validation helpers (checksums, xmllint XML edits, pluggable health checks via URL or arbitrary bash commands, permission audits).
- Optional artifact signing checks (`*.sha256`, `*.asc`, `*.sig`) enforced before changes.
- Shellcheck CI workflow (`.github/workflows/shellcheck.yml`) linting every `deploy/**/*.sh` change.
- Append-only audit trail at `state/deployments.log` plus per-host logs in `tmp/`.

📸 **Screenshots / GIFs**
- CLI-first workflow. Replay the bundled asciinema demo:

```bash
asciinema play docs/demos/dry-run-rollback.cast
```

⚡ **Quick start**

```bash
# 0. Prereqs: deploy-user can ssh to all hosts and run `sudo -u centos`
cd deploy

# 1. Prepare artifacts and inventory
ls artifacts/                # ensure JARs / ZIPs are in place
cat inventory/prod.env       # confirm ALL target hosts
# (Optional) place matching *.sha256 or *.asc files next to artifacts for signature enforcement

# 2. Dry run (no remote writes)
./deploy.sh inventory/prod.env loan-service 1.2.5 --dry-run

# 3. Real deploy with batch size 2
./deploy.sh inventory/prod.env loan-service 1.2.5 --batch-size 2

# 4. Monitor logs
tail -f state/deployments.log
```

🧠 **How it works**

```
jump server (deploy.sh)
  └─ batches hosts → tar | ssh → sudo -u centos deploy_remote.sh
	  └─ acquires locks
	  └─ sources lib/*.sh and apps/<app>/deploy.conf
	  └─ runs steps/01_* … 99_* (precheck → execute → verify)
		  └─ on failure → rollback() in reverse order
	  └─ logs to state/deployments.log + tmp/<deploy_id>_<vm>.log
```

🛡️ **Security / limitations**
- Requires `deploy-user` → `sudo -u centos` without password; `lib/security.sh` parses the remote sudoers allowlist and rejects targets/commands outside the allowed set (default: `centos` + standard bash binaries). Override `ALLOWED_SUDO_TARGETS`/`ALLOWED_SUDO_COMMANDS` if your policy differs.
- Assumes remote hosts provide `bash`, `tar`, `xmllint`, `curl`, `unzip`, `sha256sum`, `base64`; GPG verification additionally requires `gpg`.
- Dry-run is read-only but doesn’t verify artifact presence on remote hosts (happens during real run prechecks).
- Locks under `/var/run` must be cleared manually if a host crashes mid-deploy.

🗺️ **Roadmap**
- [x] Add shellcheck CI to lint step scripts automatically.
- [x] Support pluggable health-check commands per app (not just HTTP via curl).
- [x] Optionally sign artifacts (GPG/SHA) before shipping to hosts.
- [x] Provide asciinema demo of dry-run + rollback scenario.
- [x] Harden `lib/security.sh` to parse sudoers allowlists explicitly.
- [ ] Add automated rollback smoke-test harness (simulated failure) in CI.
- [ ] Expose health-check suites in `deploy.conf` with per-step timeouts & thresholds.

📚 **More docs**
- `IMPLEMENTATION.md` — deep dive into architecture, locking, and rollback design.
- `DRY_RUN.md` — walk-through of `--dry-run` outputs and log interpretation.

Last updated: 2026-01-08
