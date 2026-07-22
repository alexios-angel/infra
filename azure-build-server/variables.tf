variable "subscription_id" {
  description = "Azure subscription id. Leave null and export ARM_SUBSCRIPTION_ID instead (e.g. from `az account show --query id -o tsv`) to keep it out of any file."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the devbox"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "VM size. One box for every project: clang/LLVM release builds saturate all cores (links ~4 GB each), PCH bakes want one fast core + headroom."
  type        = string
  # 8 vCPU / 32 GiB, ~$0.31/hr pay-as-you-go in eastus. This uses 8 of the
  # subscription's 10-core eastus regional quota; Standard_F16als_v7 (16/32,
  # ~$0.60/hr — same cost per LLVM build, half the wall clock) or D16as_v7
  # need the quota raised first (aka.ms/ProdportalCRP quota blade). The idle
  # watchdog deallocates the box after 30 idle minutes, so the hourly rate
  # only bills while you're actually using it. Capacity check:
  #  az vm list-skus --location eastus --resource-type virtualMachines -o table
  default = "Standard_D8as_v7"
}

variable "use_spot" {
  description = "Run as a Spot VM (much cheaper, but can be evicted mid-build; evictions deallocate, the disk survives and ninja resumes)"
  type        = bool
  default     = false
}

variable "os_disk_gb" {
  description = "OS disk size in GB (several project trees + an llvm-project checkout + build tree + 30 GB ccache)"
  type        = number
  default     = 256

  validation {
    condition     = var.os_disk_gb >= 64
    error_message = "os_disk_gb must be at least 64 (an LLVM build tree alone outgrows less)."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized on the server"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_cidr" {
  description = "CIDR allowed to SSH in. Leave null to auto-detect your current public IP at plan time. 0.0.0.0/0 opens key-only SSH to the internet if you'd rather never re-point it."
  type        = string
  default     = null

  validation {
    condition     = var.ssh_cidr == null || can(cidrhost(var.ssh_cidr, 0))
    error_message = "ssh_cidr must be a valid CIDR (e.g. 203.0.113.7/32)."
  }
}

variable "name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "devbox"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be lowercase alphanumeric/hyphens, starting with a letter (it prefixes Azure resource names)."
  }
}
