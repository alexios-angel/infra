#!/usr/bin/env bash
# Lifecycle helper for the devbox. Usage: ./server.sh {start|stop|status|ip|ssh|ssh-config|allow-ip}
# Reads VM name + resource group from terraform output in this directory.
# NOTE: "stop" DEALLOCATES — in Azure a merely-stopped VM still bills compute.
#       (The box also deallocates itself after 30 min without activity.)
set -euo pipefail
cd "$(dirname "$0")"

vm=$(terraform output -raw vm_name)
rg=$(terraform output -raw resource_group)

current_ip() {
  terraform output -raw public_ip
}

case "${1:-status}" in
  start)
    az vm start --resource-group "$rg" --name "$vm" --output none
    echo "running at $(current_ip)"
    ;;
  stop)
    az vm deallocate --resource-group "$rg" --name "$vm" --output none
    echo "deallocated (disk persists; compute billing stops)"
    ;;
  status)
    az vm get-instance-view --resource-group "$rg" --name "$vm" \
      --query "{power: instanceView.statuses[?starts_with(code, 'PowerState/')] | [0].displayStatus, size: hardwareProfile.vmSize}" \
      --output tsv
    ;;
  ip)
    current_ip
    ;;
  ssh)
    exec ssh "ubuntu@$(current_ip)"
    ;;
  ssh-config)
    # (Re)write ONLY our managed block in ~/.ssh/config; every other entry is
    # left untouched. Projects then reach the box as plain `ssh <vm-name>`.
    cfg="$HOME/.ssh/config"
    ip=$(current_ip)
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    touch "$cfg"
    tmp=$(mktemp "$HOME/.ssh/config.XXXXXX")
    awk -v vm="$vm" '
      $0 == "# BEGIN " vm " — managed by infra/azure-build-server/server.sh" {skip=1; next}
      $0 == "# END " vm {skip=0; next}
      !skip {print}
    ' "$cfg" >"$tmp"
    {
      echo "# BEGIN $vm — managed by infra/azure-build-server/server.sh"
      echo "Host $vm"
      echo "  HostName $ip"
      echo "  User ubuntu"
      echo "# END $vm"
    } >>"$tmp"
    mv "$tmp" "$cfg"
    chmod 600 "$cfg"
    echo "wrote Host $vm -> ubuntu@$ip in $cfg"
    ;;
  allow-ip)
    # Home IPs drift. Repoint the NSG ssh rule at wherever we are now — no
    # terraform run needed, and no drift either: the next plan re-detects the
    # same IP. Works from the new network because az auth is account-based.
    myip=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
    az network nsg rule update --resource-group "$rg" --nsg-name "${vm}-nsg" \
      --name ssh --source-address-prefixes "${myip}/32" --output none
    echo "ssh now allowed from ${myip}/32"
    ;;
  *)
    echo "usage: $0 {start|stop|status|ip|ssh|ssh-config|allow-ip}" >&2
    exit 1
    ;;
esac
