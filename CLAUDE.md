# CLAUDE.md — infra

Terraform for the shared Azure **devbox** (module: `azure-build-server/`) —
the one VM every project builds on. Public repo: NEVER commit state, tfvars,
plans, real IPs, or the subscription id (env only: `export
ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)` — needed in every
shell that runs terraform).

## The contract projects rely on

- ssh alias **`devbox`** (written by `./azure-build-server/server.sh
  ssh-config`; managed block in `~/.ssh/config`, other entries untouched).
  Scripts honor `DEVBOX_HOST=ubuntu@<ip>` as an override.
- Project trees live at **`~/projects/<name>`** on the box; scratch build
  dirs (`~/llvm-build`, `~/dist`) stay in `$HOME`. llvm checkout:
  `~/projects/llvm-project`.
- Base tools come from **apt** and are on the default PATH — including for
  non-interactive `ssh devbox 'cmd'`. Anything **brew-only** is declared in
  the consuming project's Brewfile and converged with `brew bundle` at build
  time (embed's `scripts/build-clang/Brewfile` is the model); brewed
  binaries need `PATH=/home/linuxbrew/.linuxbrew/bin:$PATH` or absolute
  paths in non-interactive ssh.

## Gotchas

- **The box deallocates itself after 30 idle minutes** (activity = ssh
  sessions or load ≥ 0.5). "VM deallocated" out of nowhere is by design —
  `./server.sh start` wakes it in ~30 s. Explicit `./server.sh stop` when
  done is still good manners (skips the 30-min tail).
- **ssh suddenly times out after a network change** → your home IP rotated
  and the NSG /32 is stale: `./server.sh allow-ip` (one az call, no
  terraform, no drift).
- cloud-init runs at FIRST BOOT ONLY — editing `cloud-init.yaml` after the
  VM exists forces VM replacement on apply. Validate edits with
  `cloud-init schema --config-file azure-build-server/cloud-init.yaml`
  before applying. Boot marker: `/var/lib/cloud/instance/devbox-ready`;
  logs: `/var/log/cloud-init-output.log` (+ `/var/log/cloud-init.log`).
- The idle watchdog's role assignment needs the deploying account to hold
  Owner/User-Access-Administrator; role propagation can 403 for a few
  minutes after apply — it self-heals on the next 5-min timer tick.
