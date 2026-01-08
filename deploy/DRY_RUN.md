# Dry-run guide

This guide explains how to perform a dry-run of the deployment framework and how to interpret the output. Dry-run mode is read-only and will not perform remote writes or actual deploy actions.

## Goals of a dry-run

- Confirm inventory and target hosts.
- List the step order that will run on each VM.
- Validate that the orchestrator sees the application steps and configuration.
- Provide per-VM planned actions summary without modifying remote state.

> Important: The dry-run implemented here is conservative and intentionally performs zero remote writes. It does not fully validate artifact availability on the remote host — that will still be checked at runtime by prechecks executed on the remote host.

## Quick dry-run command

From the repo root on the jump server run:

```bash
./deploy/deploy.sh deploy/inventory/prod.env loan-service 1.2.5 --dry-run
```

- `deploy/inventory/prod.env` — inventory file path (one host per line).
- `loan-service` — the app directory under `deploy/apps/`.
- `1.2.5` — the version string used by `deploy.conf` (e.g., used to construct JAR file name).
- `--dry-run` — prevents remote writes; it lists targets and planned step order.

## Expected dry-run output

The dry-run prints:

- Deployment ID and app/version
- The list of target VMs found in the inventory
- A message: `DRY-RUN: No remote writes will be performed`
- The planned per-VM step order (basenames of `apps/<app>/steps/*.sh` in order)

Example:

```
Deployment ID: 20260108T123456Z-12345
App: loan-service Version: 1.2.5
Targets (2):
 - vm1.example.com
 - vm2.example.com
DRY-RUN: No remote writes will be performed

Planned per-VM step order:
  01_copy_jar.sh
  02_unzip_classes.sh
  03_edit_xml.sh
  04_unzip_extra.sh
  99_verify.sh
```

### Demo playback

Replay the included asciinema capture to observe a dry-run followed by an automatic rollback when a step fails:

```bash
asciinema play docs/demos/dry-run-rollback.cast
```

## Additional verification you can do before a real deployment

1. Confirm `deploy/artifacts/` contains the artifact names expected by `deploy/apps/<app>/deploy.conf`. In the sample `loan-service` the `JAR_NAME` is built using `VERSION`.
2. Ensure your `deploy/inventory/prod.env` lists all target VMs (ALL VMs must be included).
3. Ensure each target remote host is reachable over SSH from the jump server as the `deploy-user`, and that the host is present in `~/.ssh/known_hosts` (because `StrictHostKeyChecking=yes` is enforced).
4. Ensure `sudo -u centos` is allowed for the `deploy-user` on each target and that the remote host has required tools (`xmllint`, `unzip`, `curl`, `sha256sum`).

## Simulated tests to exercise steps locally (optional)

If you want to test step scripts locally (without contacting remote VMs), you can simulate the environment by extracting the deployment bundle locally and running `deploy_remote.sh` as `centos` if you have a `centos` user on your test machine. WARNING: Do not run these commands on production hosts.

Example (local simulation):

```bash
# create a temporary directory to simulate remote host
mkdir -p /tmp/deploy_sim && tar -C deploy -cz deploy_remote.sh lib apps artifacts state | tar -C /tmp/deploy_sim -xz
# if you have a local 'centos' user and sudo rights to run as centos, run:
sudo -u centos bash -c '/tmp/deploy_sim/deploy_remote.sh localhost loan-service 1.2.5 SIMDEPLOY'
```

This will run steps locally under user `centos` and will exercise prechecks and verify functions. Use with caution and only on test machines.

## Interpreting logs after a test run

- Jump server per-VM run logs are stored in `deploy/tmp/<deploy_id>_<vm>.log`.
- Local audit log is `deploy/state/deployments.log` and is append-only. Each line format:

```
timestamp | deployment_id | app | version | vm | step | message
```

Example messages to watch for:

- `precheck:fail` — step precheck failed. Check the step precheck logic and required artifacts/environment.
- `execute:fail` — step execution failed. Review the per-VM log for the error and the step's rollback result.
- `verify:fail` — verification after execute failed — rollback will be triggered.
- `rollback:fail` — rollback failed for a step; manual intervention will be required.

## Next steps after dry-run

1. Address any missing artifacts or prerequisites flagged during prechecks and validation.
2. Add missing remote host keys to `~/.ssh/known_hosts` from the jump server so `StrictHostKeyChecking=yes` will not block the deploy.
3. Run a controlled real deployment with `--batch-size 1` first:

```bash
./deploy/deploy.sh deploy/inventory/prod.env loan-service 1.2.5 --batch-size 1
```

Monitor `deploy/tmp/<deploy_id>_<vm>.log` and `deploy/state/deployments.log` for progress.

---

Document last updated: 2026-01-08
