# infra

Terraform for the shared Azure **devbox** — one general-purpose Linux VM that
every project (current and future) uses as its remote build/dev server. It
replaces the per-project build servers that used to live in
`compile-time-browser/infra/` and `embed/infra/`.

## The box

- **Standard_D8as_v7** (8 vCPU / 32 GiB, ~$0.31/hr eastus pay-as-you-go),
  256 GB Premium SSD, Ubuntu 24.04 Gen2 with Trusted Launch. Size and disk
  are variables; a resize is one `terraform apply` (deallocate + restart,
  disk persists). Spot pricing via `-var use_spot=true`.
- **Auto-deallocates after 30 idle minutes** (systemd timer +
  `devbox-idle-check`). Activity = any ssh session (interactive or exec,
  so remote builds count) or 1-min load ≥ 0.5 (detached builds count too).
  Wake it with `./server.sh start` (~30 s). The watchdog authenticates with
  the VM's managed identity — a custom role that can deallocate this VM and
  nothing else; no credentials live on the box.
- Static public IP (survives deallocate/start), SSH key-only auth, NSG
  allows port 22 from your apply-time IP only.

## Provisioning (cloud-init.yaml, first boot only)

Everything apt-installable comes from apt — build tools (cmake, ninja,
ccache, pkg-config, glm), the LLVM 18 suite (clang, lld, lldb, clangd,
clang-format, clang-tidy), and the dev environment: zsh + oh-my-zsh (gentoo
theme) as the login shell, **nightly neovim** (PPA), gh, cloudflared,
fastfetch, bat, ripgrep, xsel, htop. Third-party repos (Cloudflare, GitHub
CLI, the two PPAs) are keyring-scoped via `signed-by`; installer scripts are
pinned to commit SHAs. fail2ban and unattended-upgrades run as a matter of
course.

**linuxbrew is bootstrapped but installs nothing.** A project that needs a
brew-only dependency declares it in its own Brewfile and converges at build
time with `brew bundle --file=...` — `embed/scripts/build-clang/Brewfile` is
the model. Never ad-hoc `brew install` in scripts.

## Conventions

- Every project tree lives under **`~/projects/<name>`** on the box
  (`~/projects` is created by cloud-init). Scratch build trees (e.g.
  `~/llvm-build`, `~/dist`) stay in `$HOME`.
- Project repos reach the box through the **`devbox` ssh alias** (written by
  `./server.sh ssh-config`); scripts honor `DEVBOX_HOST=ubuntu@1.2.3.4` as
  an override. Consumers today: `compile-time-browser/tools/remote-build.sh`
  and `embed/scripts/remote-build-clang.sh`.
- State is local (single operator) and gitignored — it embeds your detected
  home-IP CIDR. The commented-out `backend "azurerm"` block in `main.tf` is
  the shared-state upgrade path. `.terraform.lock.hcl` IS committed.

## Use

```sh
az login                                                  # once
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)   # every shell
cd azure-build-server
terraform init && terraform apply
./server.sh ssh-config                                    # writes the `devbox` ssh alias
```

Day to day:

```sh
./server.sh start      # az vm start (the watchdog stopped it, or you did)
./server.sh ssh        # or just: ssh devbox
./server.sh stop       # DEALLOCATE now instead of waiting out the idle window
./server.sh status     # power state + size
./server.sh allow-ip   # your home IP changed: repoint the NSG ssh rule at it
```

`allow-ip` needs no terraform and creates no drift — the next plan
auto-detects the same IP. If you'd rather never think about it:
`terraform apply -var ssh_cidr=0.0.0.0/0` (auth stays key-only).

Teardown: `terraform destroy`.

## Secrets

There are none in this repo, and it must stay that way — it is public. The
gitignore keeps out state/tfvars/plans (they contain your home-IP CIDR and
subscription-scoped resource IDs); the subscription id travels only through
`ARM_SUBSCRIPTION_ID`. The PGP blocks inside `cloud-init.yaml` are vendors'
*public* apt-signing keys.
