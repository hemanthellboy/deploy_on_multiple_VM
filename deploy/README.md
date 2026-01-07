# Deployment Framework

Production-safe, bash-only multi-VM deployment system designed to run from a jump server with strict security controls, automatic rollback, and auditable logging.

## Features

- **Shell-only execution**: Pure bash implementation. No Python, Java, Node, or external services are required.
- **Parallel across VMs, sequential within**: Runs batches of hosts concurrently using `deploy.sh`, while each host processes steps sequentially.
- **Mandatory locking**: Enforces `/var/run/deploy-global.lock` and `/var/run/deploy.lock` ownership by `centos`; fails fast if locks exist.
- **Automatic rollback**: On any precheck/execute/verify failure, previous steps rollback in reverse order with manual-intervention markers if a rollback fails.
- **Strict security**: SSH as `deploy-user`, immediate `sudo -u centos bash -c "..."`, and `StrictHostKeyChecking=yes` across the board.
- **Rich validation**: Checksum validation, XML editing via `xmllint`, ownership and permission enforcement, runtime health checks.
- **Audit logging**: Append-only `state/deployments.log` plus per-host logs under `tmp/`.

## Directory structure (MANDATORY)

```
deploy/
├── deploy.sh                # Multi-VM orchestrator (jump server)
├── deploy_remote.sh         # Runs on each VM (as centos)
├── README.md                # (this file)
├── IMPLEMENTATION.md        # Detailed implementation deep dive
├── DRY_RUN.md               # Dry-run instructions
├── inventory/
│   └── prod.env             # List of all target VMs
├── apps/
│   └── loan-service/
│       ├── deploy.conf      # App-specific configuration
│       └── steps/           # Ordered step scripts (01_*, 02_*, ..., 99_*)
├── lib/                     # Shared bash libraries
│   ├── logger.sh
│   ├── lock.sh
│   ├── rollback.sh
│   ├── security.sh
│   ├── validation.sh
│   └── ssh.sh
├── artifacts/               # Deployment artifacts (JARs, ZIPs)
├── state/
│   └── deployments.log      # Append-only audit log
└── tmp/                     # Per-run logs and scratch space
```

## Execution model

### Orchestrator (`deploy.sh`)

```bash
./deploy.sh [inventory_file] <app> <version> [--batch-size N] [--dry-run]
```

- Reads inventory (`inventory/prod.env` by default) and splits hosts into batches.
- For each batch, streams a tar of `deploy_remote.sh`, `lib/`, `apps/<app>/`, `artifacts/`, and `state/` to each VM.
- Runs the remote script using `ssh -o StrictHostKeyChecking=yes -o BatchMode=yes` and `sudo -u centos`.
- If any host in a batch fails, aborts immediately.

Use `--dry-run` to list targets and step order without any remote writes (see `DRY_RUN.md`).

### Remote runner (`deploy_remote.sh`)

- Acquires global and per-VM locks under `/var/run`.
- Validates sudo restrictions (`lib/security.sh`).
- Sources app config (`apps/<app>/deploy.conf`) so steps know jar names, directories, etc.
- Sorts and executes `steps/*.sh` sequentially.
- For each step, calls `precheck`, `execute`, `verify`; on failure triggers `rollback` for prior steps in reverse order.
- Logs all status messages via `lib/logger.sh`.

## Step contract

Every script under `apps/<app>/steps/` **must define** the following functions:

- `precheck()` — Read-only validation before any changes.
- `execute()` — Perform the change atomically or copy with backup.
- `verify()` — Ensure the change succeeded (checksum, structure, permissions, health checks, etc.).
- `rollback()` — Revert the change; must be safe even if partially applied.

Failure in any function triggers reverse-order rollbacks, with manual intervention flagged if rollback fails.

## Security & locking requirements

- SSH exclusively as `deploy-user` with `StrictHostKeyChecking=yes` and `BatchMode=yes`.
- Immediately switch to centos: `sudo -u centos bash -c '...'` (no root login, no direct centos SSH).
- Every file manipulation, backup, rollback, validation occurs as `centos`.
- Global lock: `/var/run/deploy-global.lock`
- Per-VM lock: `/var/run/deploy.lock`
- Locks must be owned by `centos` and removed on exit.

## Validation & audit

- Checksum comparisons using `sha256sum` (in steps like `01_copy_jar.sh`).
- XML edits via `xmllint --shell`; XML validity enforced via `xmllint --noout`.
- Health checks via `curl` (configured through `deploy.conf`).
- No world-writable files; ownership must be `centos:centos`.
- Logging appended to `state/deployments.log` plus per-run logs in `tmp/` (one per VM per deployment ID).

## Artifacts & inventory

- Place deployment artifacts (JARs, ZIPs, configs) inside `artifacts/` before running the deploy.
- Maintain `inventory/prod.env` with one host per line (ALL hosts must be included). Comments (`#`) and blank lines are ignored.

## Usage examples

### Dry run

```bash
./deploy.sh deploy/inventory/prod.env loan-service 1.2.5 --dry-run
```

Outputs target list and step order; performs no remote writes.

### Production run (batch size 2)

```bash
./deploy.sh deploy/inventory/prod.env loan-service 1.2.5 --batch-size 2
```

Monitor per-VM logs generated under `tmp/` and the central audit log `state/deployments.log`.

## Troubleshooting tips

- If a deployment fails, check `tmp/<deploy_id>_<vm>.log` for the VM log.
- Inspect `state/deployments.log` for aggregate status and step-level outcomes.
- Stale locks under `/var/run` will block new deployments—investigate before removing.
- Rollbacks leave backups (e.g., `.backup` dirs for JARs and classes). Clean them up after verifying success.

## Extending the framework

- Add new applications under `apps/<new-app>/` with a `deploy.conf` and ordered `steps/01_*.sh ...` scripts.
- Reuse helpers in `lib/validation.sh` to keep verification consistent.
- Keep scripts compatible with `bash -n` (run `find deploy -name '*.sh' -exec bash -n {} \;`).
- Ensure new functionality respects security, locking, and rollback guarantees.

## Additional documentation

- `IMPLEMENTATION.md` — deep dive into architecture, control flow, and safety decisions.
- `DRY_RUN.md` — detailed dry-run walkthroughs and interpretation of output.

---

Last updated: 2026-01-08
