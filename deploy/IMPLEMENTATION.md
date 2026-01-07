# Deployment framework — Implementation document

## Purpose

This document explains the implementation, file-by-file, the control flow, security constraints, and operational procedures for the bash-only, jump-server executed, multi-VM deployment framework located in `deploy/`.

Follow these instructions carefully in production. The framework enforces strict security rules (SSH with StrictHostKeyChecking, no root/centos SSH, all remote work performed as `centos` via `sudo -u centos`), mandatory locking, automatic rollback, and per-step verification.

## High-level flow

- `deploy/deploy.sh` (run on the jump server) reads the inventory and orchestrates multi-VM deployment in configurable batches. For each VM in a batch it:
  - Streams a tarball of `deploy_remote.sh`, `lib/`, `apps/<app>/`, `artifacts/`, and `state/` to the remote host.
  - Executes that tarball on the remote host using `ssh` and `sudo -u centos bash -c '.../deploy_remote.sh ...'` so all file operations happen as `centos`.
  - Runs the remote runners in parallel per batch and waits for their completion; if any VM fails the batch the orchestrator exits with failure.

- `deploy/deploy_remote.sh` (runs on the remote host as `centos`) is the per-VM step executor. It:
  - Acquires the global lock (`/var/run/deploy-global.lock`) and per-VM lock (`/var/run/deploy.lock`) (both must be owned by `centos`). If locks exist, it fails fast.
  - Sources `lib/*.sh` and the app's `deploy.conf`.
  - Executes steps in `apps/<app>/steps/` in lexical order. For each step it calls `precheck()`, `execute()`, `verify()`.
  - On any step failure it calls the rollback engine which calls `rollback()` for executed steps in reverse order.
  - Releases locks and writes audit log entries to the provided `state/deployments.log`.

## Directory & file overview

Required directory structure (do not change):

```
deploy/
├── deploy.sh
├── deploy_remote.sh
├── inventory/
│   └── prod.env
├── apps/
│   └── loan-service/
│       ├── deploy.conf
│       └── steps/
│           ├── 01_copy_jar.sh
│           ├── 02_unzip_classes.sh
│           ├── 03_edit_xml.sh
│           ├── 04_unzip_extra.sh
           └── 99_verify.sh
├── lib/
│   ├── logger.sh
│   ├── lock.sh
│   ├── rollback.sh
│   ├── security.sh
│   ├── validation.sh
│   └── ssh.sh
├── artifacts/
├── state/
│   └── deployments.log
└── tmp/
```

Key files and responsibilities:

- `deploy/deploy.sh` — orchestrator. Runs on jump server. Arguments: `[inventory_file] <app> <version> [--batch-size N] [--dry-run]`.
  - Behavior: For each batch it streams a tarball to each VM and runs `deploy_remote.sh` there under `centos` using `sudo -u centos`. Starts remote runs in background and waits for completion.
  - Dry-run: `--dry-run` prints target VMs and planned step order and performs no remote writes.

- `deploy/deploy_remote.sh` — per-VM runner. Runs on the remote VM as `centos`.
  - Responsibilities: Lock acquisition, security checks, step iteration, rollback on failure, audit logging, lock release.
  - Inputs: VM (string), APP (name), VERSION, DEPLOY_ID.

- `deploy/lib/logger.sh` — logging helpers. Two helper functions:
  - `log_remote` (writes into the remote `$STATE_FILE` and echoes a line to stdout).
  - `log_local` (appends to `deploy/state/deployments.log` on the jump server).
  - Log format (per line): `timestamp | deployment_id | app | version | vm | step | message`.

- `deploy/lib/lock.sh` — global and per-VM lock helpers. Paths:
  - Global lock: `/var/run/deploy-global.lock`
  - Per-VM lock: `/var/run/deploy.lock`
  - The script writes the PID to the lock file and attempts to `chown centos:centos` the file.

- `deploy/lib/rollback.sh` — rollback engine. Exposes `rollback_sequence` which accepts an array of executed step script paths and calls each step's `rollback()` in reverse order. On rollback failure it writes an explicit manual-intervention marker to the state log.

- `deploy/lib/security.sh` — basic sudo allowlist check heuristics. It currently examines `sudo -l` output for `centos` and tests `sudo -n -u centos true` as an existence check. Replace with a stricter check for your environment.

- `deploy/lib/validation.sh` — file/ownership/XML/health-check helpers used by step `verify()` implementations. Functions exported:
  - `validate_file_exists`, `validate_owned_by_centos`, `validate_no_world_writable`, `validate_xml`, `health_check_url`.

- `deploy/lib/ssh.sh` — minimal SSH wrapper which enforces `StrictHostKeyChecking=yes`.

- `deploy/inventory/prod.env` — inventory file. One host per line. Comments supported.

- `deploy/apps/<app>/deploy.conf` — application config. Example variables found in the sample `loan-service`:
  - `APP_NAME`, `JAR_NAME` (this file may reference `VERSION` which `deploy_remote.sh` exports before sourcing), `TARGET_LIB_DIR`, `TARGET_CLASSES_DIR`, `EXTRA_ZIPS`, `XML_PATH`, `XML_EDITS`, `HEALTH_URL`.

- `deploy/apps/<app>/steps/*.sh` — step scripts. Must implement the contract (see below) and be idempotent where possible.

## Step contract (strict)

Each step script in `apps/<app>/steps/` must define four functions with these exact names and semantics:

- precheck(): quick read-only checks to decide if the step can proceed. Should return 0 for OK, non-zero for failure.
- execute(): perform the action (file copies, extraction, edits). Must be atomic where possible or leave a backup so rollback can restore.
- verify(): post-action validation. If verification fails deploy_remote will immediately rollback.
- rollback(): restore previous state (reverse the execute). Must be safe to run even if partially applied.

Order of execution: steps are executed in lexical sort order (e.g., `01_...`, `02_...`, ... `99_...`).

Rollback behavior: on any failure in precheck/execute/verify of a step, the rollback engine will call rollback() for all previously executed steps in reverse order. Any rollback failure is logged and marks the VM as requiring manual intervention.

Examples of step behavior (see `apps/loan-service/steps`):

- `01_copy_jar.sh` — copies `artifacts/$JAR_NAME` to the target lib dir, creates a timestamped backup of the previous JAR, verifies checksum with `sha256sum`, enforces ownership `centos:centos`, and rollback restores the backup.
- `02_unzip_classes.sh` — extracts `artifacts/classes.zip` to a temporary directory, validates structure contains `WEB-INF`, backs up existing classes dir (`classes.bak.<ts>`), and atomically moves the new dir in place.
- `03_edit_xml.sh` — creates a timestamped backup of `application.xml` and uses `xmllint --shell` to set values (no regex). Rollback restores the latest backup.
- `04_unzip_extra.sh` — optional extra zip extraction and merge into classes dir.
- `99_verify.sh` — final checks: files exist, ownership, no world-writable files, xmllint validation, HTTP health-check with `curl`.

## Locking (mandatory)

- Lock files must be created under `/var/run` and owned by `centos`.
- If a lock file exists at the start of `deploy_remote.sh` the script fails fast.
- Locks are released on exit via traps. If a process crashes or a host reboots leaving a stale lock, manual investigation is required.

## Security model

- SSH from jump server is done as the `deploy-user` (normal account). `deploy.sh` uses `ssh -o StrictHostKeyChecking=yes -o BatchMode=yes`.
- The orchestrator never SSHes as `root` or `centos`.
- Once connected, `deploy.sh` invokes `sudo -u centos bash -c '...deploy_remote.sh...'` on the remote host, so all file manipulations, backups, rollbacks, and validations are executed by the `centos` account.
- `lib/security.sh` runs a heuristic check to ensure the sudo allowlist includes the centos switch; adapt this to your environment to make it strict and auditable.

## Audit logging

- Log entries are appended to `deploy/state/deployments.log` on the jump server (local) and also to the remote `$STATE_FILE` inside the extracted remote bundle; in normal operation the remote runner echoes the same log lines so the orchestrator captures per-VM run logs into `deploy/tmp/<deploy_id>_<vm>.log`.
- Log format: `timestamp | deployment_id | app | version | vm | step | message`.

## Dependencies and remote requirements

Remote hosts (the VMs) must have the following utilities installed and available in `PATH` for the respective steps to work:

- `xmllint` (libxml2-utils) — required by `03_edit_xml.sh` and `validation.validate_xml`.
- `unzip` — required by unzip steps.
- `curl` — required for runtime health checks.
- `sha256sum` (or `shasum -a 256` equivalent). The current scripts use `sha256sum`.

If any remote host lacks these tools a precheck or verify will fail and rollback will be executed.

## Artifacts handling

- The orchestrator sends the `deploy/` bundle (deploy_remote.sh, lib, apps/<app>, artifacts, state) to each VM at runtime using a tar stream over SSH. Artifacts should be placed under `deploy/artifacts/` prior to running `deploy.sh`.
- Steps should only read artifacts from `$BASE_DIR/artifacts` (remote extracted location) and must copy them into production locations under centos ownership.

## How to add a new application

1. Create `deploy/apps/<new-app>/deploy.conf` and set the required variables (target dirs, jar name format, xml path, health URL, any EXTRA_ZIPS, XML_EDITS array if you need XML edits).
2. Implement step scripts `apps/<new-app>/steps/01_...` following the step contract. Keep the number ordering to control step sequence.
3. Add artifacts to `deploy/artifacts/` with the expected names referenced in `deploy.conf`.
4. Run a dry-run and then a controlled deploy with a single or small batch.

## Troubleshooting

- If `deploy.sh` reports a VM failed, find the per-VM logs in `deploy/tmp/<deploy_id>_<vm>.log` on the jump server. Those logs also contain the remote `log_remote` outputs.
- If rollback reports manual intervention required, inspect the remote machine for partial backups in the target directories (e.g., `TARGET_LIB_DIR/.backup`, `TARGET_CLASSES_DIR.bak.*`) and check `/var/run/deploy.lock` to see stale lock ownership.
- If xmllint edits fail, verify the `XML_EDITS` entries in `deploy.conf` and test them manually using `xmllint --shell` on a staging VM.

## Safety and best practices

- Always perform `--dry-run` first and then a single-VM deploy to validate end-to-end before increasing `--batch-size`.
- Ensure your jump server keys and known_hosts are managed and that `StrictHostKeyChecking=yes` will not block you during bootstrap — add hosts to `known_hosts` before running.
- Keep `artifacts/` and `deploy/inventory/prod.env` in a secure place with restricted permissions. Use GPG signatures for artifacts if you require further assurance.

## Appendices

- For exact implementation details see the scripts in `deploy/lib/` and `deploy/apps/loan-service/steps/`.
- If you require additional features (GPG verification, incremental rollout percentages, circuit-breaker on slow health checks), I can add them while preserving the strict safety model.

---

Document last updated: 2026-01-08
