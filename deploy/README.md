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
- Validation helpers (checksums, xmllint XML edits, curl health checks, permission audits).
- Append-only audit trail at `state/deployments.log` plus per-host logs in `tmp/`.

📸 **Screenshots / GIFs**
- CLI-only workflow. If you capture terminal recordings (e.g., asciinema), link or embed them here.

⚡ **Quick start**

```bash
# 0. Prereqs: deploy-user can ssh to all hosts and run `sudo -u centos`
cd deploy

# 1. Prepare artifacts and inventory
ls artifacts/                # ensure JARs / ZIPs are in place
cat inventory/prod.env       # confirm ALL target hosts

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
- Requires `deploy-user` → `sudo -u centos` without password; sudo allowlist is validated heuristically (harden `lib/security.sh` to match your policy).
- Assumes remote hosts provide `bash`, `tar`, `xmllint`, `curl`, `unzip`, `sha256sum`.
- Dry-run is read-only but doesn’t verify artifact presence on remote hosts (happens during real run prechecks).
- Locks under `/var/run` must be cleared manually if a host crashes mid-deploy.

🗺️ **Roadmap**
- [ ] Add shellcheck CI to lint step scripts automatically.
- [ ] Support pluggable health-check commands per app (not just HTTP via curl).
- [ ] Optionally sign artifacts (GPG/SHA) before shipping to hosts.
- [ ] Provide asciinema demo of dry-run + rollback scenario.
- [ ] Harden `lib/security.sh` to parse sudoers allowlists explicitly.

📚 **More docs**
- `IMPLEMENTATION.md` — deep dive into architecture, locking, and rollback design.
- `DRY_RUN.md` — walk-through of `--dry-run` outputs and log interpretation.

Last updated: 2026-01-08
